class ApplicationController < ActionController::Base
  include Pundit::Authorization
  # Phase 5(d) defense-in-depth: assert the Apartment schema matches the request host.
  # LOG-ONLY until config.x.enforce_tenant_boundary (default OFF) is flipped.
  include TenantBoundary
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session, if: proc { |c| c.request.format == 'application/json' }

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
  # rendering a STATIC 403 — NOT redirect_to root_url (root is organizations#index, < ApplicationController;
  # under check_authorization it would itself raise this, looping forever and locking out every user). A
  # direct render cannot loop. Inert until config.x.enforce_authorization is flipped.
  rescue_from CanCan::AuthorizationNotPerformed do |e|
    AccessLog.security_event!(
      event_type: 'authorization_not_performed',
      request: request,
      user: current_user,
      metadata: { 'reason' => e.message, 'controller' => controller_path, 'action' => action_name }
    )
    render plain: 'Not authorized', status: :forbidden, layout: false
  end

  def current_organization
    Organization.current
  end

  private

  def configure_permitted_parameters
    # Devise 4 (Rails 5) replaced the `.for(scope) << :attr` sanitizer API with
    # `.permit(scope, keys: [...])`. Same allow-list, current idiom.
    devise_parameter_sanitizer.permit(:account_update, keys: [
      :first_name, :last_name, :date_of_birth, :job_title, :department_id,
      :start_date, :province_id, :mobile, :task_notify, :calendar_integration,
      :pin_number, :program_warning, :staff_performance_notification
    ])
  end

  # FedRAMP IA-2(1): privileged accounts (admin + managers) must use MFA. Enforcement is gated behind
  # config.x.enforce_mfa_for_privileged (default OFF — see config/initializers/two_factor.rb), so this
  # is a no-op until the org switches it on. When on, a privileged user without MFA is sent to enroll.
  def require_mfa_for_privileged
    return unless Rails.configuration.x.enforce_mfa_for_privileged
    return unless user_signed_in? && current_user.mfa_privileged? && !current_user.two_factor_enabled?
    return if devise_controller? || controller_name == 'two_factor_settings'

    redirect_to two_factor_settings_path,
                alert: t('two_factor.enrollment_required',
                         default: 'Your role requires two-factor authentication. Please set it up to continue.')
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
