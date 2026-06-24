require 'rqrcode'

# Self-service TOTP MFA enrollment — FedRAMP IA-2(1). MFA is opt-in: a signed-in user enables it here.
# Enrollment flow: GET #show generates (once) and persists an otp_secret and renders the QR; the user
# scans it and submits a code to POST #create, which verifies the code, flips otp_required_for_login on,
# and issues one-time recovery codes. #destroy turns MFA back off.
class TwoFactorSettingsController < ApplicationController
  before_action :authenticate_user!

  def show
    @user = current_user
    unless @user.two_factor_enabled?
      # Persist a secret the first time so the QR is stable across reloads (harmless while
      # otp_required_for_login is still false — it does not affect login until enrollment completes).
      @user.update!(otp_secret: User.generate_otp_secret) if @user.otp_secret.blank?
      @provisioning_uri = @user.otp_provisioning_uri("CaseLight (#{@user.email})", issuer: 'CaseLight')
      @qr_svg = RQRCode::QRCode.new(@provisioning_uri).as_svg(module_size: 4, use_path: true, viewbox: true)
    end
  end

  def create
    @user = current_user
    if @user.validate_and_consume_otp!(params[:otp_attempt].to_s)
      @user.otp_required_for_login = true
      @codes = @user.generate_otp_backup_codes!
      @user.save!
      render :backup_codes
    else
      redirect_to two_factor_settings_path,
                  alert: t('two_factor.invalid_code', default: 'That code was not valid — check the time on your authenticator and try again.')
    end
  end

  def destroy
    current_user.update!(otp_required_for_login: false, otp_secret: nil,
                         otp_backup_codes: nil, consumed_timestep: nil)
    redirect_to two_factor_settings_path,
                notice: t('two_factor.disabled', default: 'Two-factor authentication has been turned off.')
  end

  # Issue a fresh set of recovery codes (invalidates the previous set).
  def regenerate_backup_codes
    @user = current_user
    return redirect_to(two_factor_settings_path) unless @user.two_factor_enabled?

    @codes = @user.generate_otp_backup_codes!
    @user.save!
    render :backup_codes
  end
end
