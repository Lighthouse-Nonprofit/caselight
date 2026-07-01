class ApplicationController < ActionController::Base
  include Pundit::Authorization
  # Phase 5(d) defense-in-depth: assert the Apartment schema matches the request host.
  # LOG-ONLY until config.x.enforce_tenant_boundary (default OFF) is flipped.
  include TenantBoundary
  # Phase 5.5 (AC-6) least-privilege SHADOW: LOG-ONLY until config.x.enforce_least_privilege
  # (default OFF) is flipped -- records what the narrowed ProgressNote/version rules WOULD deny.
  include LeastPrivilegeShadow
  # Phase 5.6 (AC-3) GLOBAL AUTHORIZATION CUTOVER -- SHADOW: LOG-ONLY until config.x.enforce_authorization
  # (default OFF). Records (controller/action/role only) which actions WOULD fail the mandatory check.
  include AuthorizationShadow
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session, if: proc { |c| c.request.format == 'application/json' }

  # Phase 5.6 (AC-3): GLOBAL authorization cutover. check_authorization registers a single after_action
  # that raises CanCan::AuthorizationNotPerformed for any action that neither authorized a resource
  # (authorize!/load_and_authorize_resource set @_authorized) NOR opted out via skip_authorization_check.
  # Gated on the EXISTING Phase-5.0 flag (default OFF): flag OFF => the if: predicate is false => the
  # after_action returns WITHOUT raising => byte-identical to today. Flag ON => the existing static-403
  # rescue_from catches the raise. The predicate reads config.x live, so the route-smoke can force it ON.
  check_authorization if: :enforce_authorization?

  # Belt-and-suspenders: RequestStore's Rack middleware clears its store each request, but a defensive
  # per-request reset guarantees the enforcement-flag memo can never leak across requests on a pooled
  # thread (tenant-keyed too). Cheap: a single Hash#delete of one key.
  before_action { EnforcementSetting.clear_cache! }
  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :find_association, if: :devise_controller?
  before_action :set_locale
  before_action :set_paper_trail_whodunnit
  before_action :require_mfa_for_privileged

  rescue_from ActiveRecord::RecordNotFound do |exception|
   render file: "#{Rails.root}/app/views/errors/404", layout: false, status: :not_found
  end

  helper_method :current_organization

  # AC-3 / AU-2: an authorization denial is a security-relevant event. Record an
  # access_denied AccessLog row (tenant-isolated, append-only) BEFORE redirecting.
  # security_event! also emits the structured Rails.logger line and never raises
  # into the request, so the existing redirect behavior is unchanged.
  rescue_from CanCan::AccessDenied do |e|
    AccessLog.security_event!(
      event_type: 'access_denied',
      request: request,
      user: current_user,
      metadata: { 'reason' => e.message, 'source' => 'cancan' }
    )
    redirect_to root_url, alert: e.message
  end

  rescue_from Pundit::NotAuthorizedError do |e|
    AccessLog.security_event!(
      event_type: 'access_denied',
      request: request,
      user: current_user,
      metadata: { 'reason' => e.message, 'source' => 'pundit' }
    )
    redirect_to root_url, alert: t('unauthorized.default')
  end

  # Phase 5(a)/AC-3: under the global verify_authorized cutover (Phase 5.6) an action that neither
  # authorized nor opted out raises this. Without a rescue it 500s. We log it and FAIL CLOSED by
  # rendering the value-free errors/403 view with layout: false — NOT redirect_to root_url (root is
  # organizations#index, < ApplicationController; under check_authorization it would itself raise this,
  # looping forever and locking out every user). A direct render with no layout cannot loop or
  # re-trigger auth/masking. Inert until config.x.enforce_authorization is flipped.
  rescue_from CanCan::AuthorizationNotPerformed do |e|
    AccessLog.security_event!(
      event_type: 'authorization_not_performed',
      request: request,
      user: current_user,
      metadata: { 'reason' => e.message, 'controller' => controller_path, 'action' => action_name }
    )
    render template: 'errors/403', status: :forbidden, layout: false
  end

  def current_organization
    Organization.current
  end

  private

  # Phase 5.6 (AC-3): SHADOW-FIRST switch for the global cutover. True ONLY when the org has flipped
  # config.x.enforce_authorization. While false, check_authorization's after_action is inert AND the
  # gated authorize! calls in the four formerly-default-open holes are inert (byte-identical to today).
  def enforce_authorization?
    # Phase 5 capstone: read the PERSISTED per-tenant override if set, else the config.x boot default.
    # EnforcementSetting.enabled? fails SAFE to the config.x default (OFF) on any store error, so this
    # predicate can never accidentally turn enforcement ON. With no override row it returns exactly the
    # config.x value the route-smoke spec forces -> no Phase-5 regression.
    EnforcementSetting.enabled?(:enforce_authorization,
                                config_default: Rails.application.config.x.enforce_authorization == true)
  end

  def configure_permitted_parameters
    # Devise 4 (Rails 5) replaced the `.for(scope) << :attr` sanitizer API with
    # `.permit(scope, keys: [...])`. Same allow-list, current idiom.
    devise_parameter_sanitizer.permit(:account_update, keys: [
      :first_name, :last_name, :date_of_birth, :job_title, :department_id,
      :start_date, :province_id, :mobile, :task_notify, :calendar_integration,
      :pin_number, :program_warning, :staff_performance_notification
    ])
  end

  # FedRAMP IA-2(1). Two independent ENROLL-NUDGE scopes, additive:
  #   - config.x.enforce_mfa_for_privileged (boot flag, default OFF): nudge PRIVILEGED users (admin+mgrs).
  #   - EnforcementSetting require_mfa (panel three-state, default OFF): nudge ALL signed-in users.
  # A signed-in user WITHOUT 2FA is nudged if they fall in the currently-required scope. It is an ENROLL
  # NUDGE (redirect to the reachable enrollment page), NEVER a hard block: the devise / two_factor_settings
  # / enforcement_settings exemptions keep login, the enroll page, and THIS admin panel reachable, so an
  # admin who flips require_mfa ON can still enroll AND still reach the panel to flip it back. With
  # require_mfa unset AND config.x.enforce_mfa_for_privileged OFF, nobody is nudged => byte-identical to today.
  def require_mfa_for_privileged
    return unless user_signed_in?
    return if current_user.two_factor_enabled? # already enrolled -> nothing to nudge

    require_all        = EnforcementSetting.enabled?(:require_mfa, config_default: false)
    require_privileged = Rails.configuration.x.enforce_mfa_for_privileged && current_user.mfa_privileged?
    return unless require_all || require_privileged

    # Reachability escape hatches (nudge-not-block): the enroll page + login/logout + THIS panel.
    return if devise_controller?
    return if %w[two_factor_settings enforcement_settings].include?(controller_name)

    redirect_to two_factor_settings_path,
                alert: t('two_factor.enrollment_required',
                         default: 'Two-factor authentication is required for your account. Please set it up to continue.')
  end

  # Audit context for the structured (lograge) request log — FedRAMP AU-3. Rails calls this for every
  # request's process_action instrumentation; lograge reads these payload keys (see
  # config/initializers/lograge.rb) to tag each log line with who/what/where/when.
  def append_info_to_payload(payload)
    super
    payload[:request_id] = request.request_id
    payload[:user_id]    = current_user&.id
    payload[:tenant]     = (Apartment::Tenant.current rescue nil)
    payload[:remote_ip]  = request.remote_ip
  end

  def find_association
    @department = Department.order(:name)
    @province   = Province.order(:name)
  end

  def set_locale
    locale = I18n.available_locales.include?(params[:locale].to_sym) ? params[:locale] : I18n.locale if params[:locale].present?
    if detect_browser.present?
      flash.clear
      flash[:alert] = detect_browser
    end
    I18n.locale = locale || I18n.locale
  end

  def default_url_options(options = {})
    { locale: I18n.locale }.merge(options)
  end

  def after_sign_out_path_for(_resource_or_scope)
    # Stay on the current tenant host (request.host) — request.domain drops everything but the
    # registrable domain (e.g. nip.io on cases.<ip>.nip.io), producing a dead host.
    root_url(host: request.host)
  end

  def detect_browser
    lang = params[:locale] || locale.to_s
    if browser.firefox? && browser.platform.mac? && lang == 'km'
      "Application is not translated properly for Firefox on Mac, we're sorry to suggest to use Google Chrome browser instead."
    end
  end
end
