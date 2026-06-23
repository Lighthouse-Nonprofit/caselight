class ApplicationController < ActionController::Base
  include Pundit::Authorization
  # Prevent CSRF attacks by raising an exception.
  # For APIs, you may want to use :null_session instead.
  protect_from_forgery with: :null_session, if: proc { |c| c.request.format == 'application/json' }

  before_action :configure_permitted_parameters, if: :devise_controller?
  before_action :find_association, if: :devise_controller?
  before_action :set_locale
  before_action :set_paper_trail_whodunnit

  rescue_from ActiveRecord::RecordNotFound do |exception|
   render file: "#{Rails.root}/app/views/errors/404", layout: false, status: :not_found
  end

  helper_method :current_organization

  rescue_from CanCan::AccessDenied do |exception|
    redirect_to root_url, alert: exception.message
  end

  rescue_from Pundit::NotAuthorizedError do |exception|
    redirect_to root_url, alert: t('unauthorized.default')
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
