class SessionsController < Devise::SessionsController
  include WebauthnRelyingParty

  before_action :set_whodunnit, :set_current_ngo, :detect_browser
  # The Visit row is recorded only once the user is ACTUALLY signed in — for MFA accounts that is
  # the verify_otp step, not the (deferred) first-factor create; for passkeys, the passkey_callback step.
  after_action :increase_visit_count, only: [:create, :verify_otp, :passkey_callback], if: :user_signed_in?

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

  # --- Passwordless PASSKEY (WebAuthn) login — FedRAMP IA-2 ---------------------------------------
  # A THIRD, parallel sign-in path that lives ENTIRELY in its own endpoints and never touches the
  # password/OTP code paths above. A verified passkey with user-verification is itself multi-factor
  # (possession of the authenticator + a PIN/biometric), so on success we call the SAME
  # `sign_in(resource_name, user)` that #verify_otp uses — slotting in as a parallel completed login.
  #
  # Because the passkey is inherently MFA, this path legitimately does NOT route through the separate
  # TOTP screen even for otp_required_for_login users. That is correct (it is not a bypass of the
  # require_mfa_for_privileged intent — the user has presented two factors), and is documented as such.

  # POST /users/passkey/options — issue authentication options + stash the challenge.
  # Optionally scoped to an email so a non-discoverable authenticator gets an allow-list; with no email
  # we issue an empty allow-list for the discoverable/resident-key (usernameless) flow.
  def passkey_options
    email = params[:email].to_s.strip.downcase
    allow = []
    if email.present?
      user  = resource_class.find_for_database_authentication(email: email)
      allow = user ? user.webauthn_credentials.pluck(:external_id) : []
    end

    options = relying_party.options_for_authentication(allow: allow, user_verification: 'preferred')
    session[:webauthn_authentication_challenge] = options.challenge
    render json: options
  end

  # POST /users/passkey/callback — verify the assertion and, on success, sign the user in.
  def passkey_callback
    challenge = session.delete(:webauthn_authentication_challenge)
    return render(json: { error: 'No passkey sign-in in progress.' }, status: :unprocessable_entity) if challenge.blank?

    credential_hash = passkey_credential_param
    stored = WebauthnCredential.find_by(external_id: credential_hash['id'] || credential_hash[:id])
    return render(json: { error: 'Unknown passkey.' }, status: :unprocessable_entity) unless stored

    relying_party.verify_authentication(
      credential_hash, challenge,
      public_key:       stored.public_key,
      sign_count:       stored.sign_count,
      user_verification: true
    ) do |verified|
      # `verified` is the verified credential; persist the new signature counter (cloned-authenticator
      # detection) and the last-used timestamp.
      stored.update!(sign_count: verified.sign_count, last_used_at: Time.current)
    end

    user = stored.user
    # Mirror #verify_otp: a completed authentication clears any accumulated lockable counter.
    user.update_column(:failed_attempts, 0) if user.failed_attempts.to_i.positive?
    sign_in(resource_name, user)
    set_flash_message!(:notice, :signed_in)
    render json: { redirect: after_sign_in_path_for(user) }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
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

  # The assertion from navigator.credentials.get(...). Permit the exact WebAuthn authentication shape
  # (no `permit!` — Brakeman mass-assignment) and hand a plain string-keyed hash to
  # WebAuthn::RelyingParty#verify_authentication. clientExtensionResults' keys are extension-defined.
  def passkey_credential_param
    params.require(:credential)
          .permit(:id, :rawId, :type, :authenticatorAttachment,
                  response: %i[clientDataJSON authenticatorData signature userHandle],
                  clientExtensionResults: {})
          .to_h
  end
end
