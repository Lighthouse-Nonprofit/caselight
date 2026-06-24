class SessionsController < Devise::SessionsController
  before_action :set_whodunnit, :set_current_ngo, :detect_browser
  # The Visit row is recorded only once the user is ACTUALLY signed in — for MFA accounts that is
  # the verify_otp step, not the (deferred) first-factor create.
  after_action :increase_visit_count, only: [:create, :verify_otp], if: :user_signed_in?

  # POST /users/sign_in — first factor (email + password).
  #
  # Two-step MFA: if the account has MFA enabled AND the password is correct AND the account is not
  # locked, we do NOT sign the user in here — we stash a pending reference and send them to the
  # second-factor screen (#two_factor_challenge). EVERY other case (no MFA, wrong password, locked
  # account) falls through to Devise/warden unchanged, so :lockable counting, rack-attack throttling,
  # and the standard failure messages keep working. A correct password alone never yields a signed-in
  # session for an MFA account, so there is no password-only bypass (see #verify_otp).
  def create
    creds = params.fetch(resource_name, {})
    user  = resource_class.find_for_database_authentication(email: creds[:email].to_s.strip)

    if user&.otp_required_for_login && !user.access_locked? && user.valid_password?(creds[:password].to_s)
      session[:otp_pending_user_id]  = user.id
      session[:otp_pending_remember] = creds[:remember_me]
      return redirect_to two_factor_challenge_path
    end

    super
  end

  # GET /users/two_factor — the second-factor screen. Reachable only mid-login (a pending first factor).
  def two_factor_challenge
    redirect_to(new_user_session_path) and return unless pending_two_factor_user
  end

  # POST /users/two_factor — verify a TOTP code or a one-time recovery code, then complete sign-in.
  def verify_otp
    user = pending_two_factor_user
    unless user
      redirect_to(new_user_session_path,
                  alert: t('two_factor.session_expired', default: 'Your sign-in session expired. Please log in again.'))
      return
    end

    code = params[:otp_attempt].to_s.strip
    if user.validate_and_consume_otp!(code) || consume_backup_code(user, code)
      # A successful second factor clears any accumulated lock counter, mirroring Devise's
      # reset-on-successful-authentication behaviour (we bypassed the warden strategy here).
      user.update_column(:failed_attempts, 0) if user.failed_attempts.to_i.positive?
      remember = session.delete(:otp_pending_remember)
      session.delete(:otp_pending_user_id)
      user.remember_me = true if ActiveModel::Type::Boolean.new.cast(remember)
      sign_in(resource_name, user)
      set_flash_message!(:notice, :signed_in)
      redirect_to after_sign_in_path_for(user)
    else
      flash.now[:alert] = t('two_factor.invalid_code',
                            default: 'That code was not valid — check the time on your authenticator and try again, or use a recovery code.')
      render :two_factor_challenge, status: :unprocessable_entity
    end
  end

  def set_whodunnit
    if current_user
      PaperTrail::Version.where(item_id: current_user.id, whodunnit: nil).each do |v|
        v.update(whodunnit: current_user.id)
      end
    end
  end

  def set_current_ngo
    @current_ngo = Organization.current
  end

  def detect_browser
    lang = params[:locale] || locale.to_s
    if browser.firefox? && browser.platform.mac? && lang == 'km'
      flash.clear
      flash[:alert] = "Application is not translated properly for Firefox on Mac, we're sorry to suggest to use Google Chrome browser instead."
    end
  end

  def increase_visit_count
    Visit.create(user: current_user)
  end

  private

  # The user who passed the first factor this login but has not yet completed MFA. Nil unless a
  # first factor is pending — which is what makes the OTP screen unusable on its own.
  def pending_two_factor_user
    id = session[:otp_pending_user_id]
    id && resource_class.find_by(id: id)
  end

  # Spend a one-time recovery code; persist the consumption. Returns false when the code matches none.
  def consume_backup_code(user, code)
    user.invalidate_otp_backup_code!(code) && user.save!
  end
end
