class SessionsController < Devise::SessionsController
  include WebauthnRelyingParty

  # Phase 5.6 (AC-3) allowlist: custom two-step-MFA + passkey LOGIN controller. Every action runs while
  # UNauthenticated or mid-login establishing the session -- no current_user/resource to authorize.
  # Warden/Devise gate it. AuthN, not AuthZ.
  skip_authorization_check

  before_action :set_whodunnit, :set_current_ngo, :detect_browser
  # The Visit row is recorded only once the user is ACTUALLY signed in — for MFA accounts that is
  # the verify_otp step, not the (deferred) first-factor create; for passkeys, the passkey_callback step.
  # `if: :session_user` (NOT :user_signed_in?) — see the comment on #session_user: the Devise
  # predicate runs the Warden strategies against the still-present sign-in params and corrupts the
  # :lockable counter on MFA accounts.
  after_action :increase_visit_count, only: [:create, :verify_otp, :passkey_callback], if: :session_user

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

    # AC-7 — RESTORE Devise's expired-lock cleanup on this path. Devise clears BOTH `locked_at` and
    # the accumulated `failed_attempts` inside `valid_for_authentication?` (`unlock_access! if
    # lock_expired?`), but the MFA branch below deliberately bypasses that method by calling
    # `valid_password?` directly — so without this, an expired lock leaves a stale `locked_at` and an
    # inflated counter behind. The counter is then already at/over `maximum_attempts`, and the next
    # single mistyped password re-locks the account instantly, for another full unlock window.
    # `locked_at` present while `access_locked?` is false is precisely "the unlock window elapsed"
    # (`access_locked?` == `locked_at && !lock_expired?`), using only Devise's public API.
    user.unlock_access! if user&.persisted? && user.locked_at.present? && !user.access_locked?

    if user&.otp_required_for_login && !user.access_locked? && user.valid_password?(creds[:password].to_s)
      # The pending-2FA window MUST be fully unauthenticated. sign_out here drops any existing session
      # AND forgets the remember-me cookie, so (a) a remember cookie cannot silently skip the OTP step
      # (an MFA bypass), and (b) the challenge page never renders the authenticated chrome — which
      # SessionsController (not an AdminController) does not populate. Set the pending markers AFTER.
      sign_out(resource_name)
      session[:otp_pending_user_id]  = user.id
      session[:otp_pending_remember] = creds[:remember_me]
      return redirect_to two_factor_challenge_path
    end

    super
  end

  # GET /users/two_factor — the second-factor screen. Reachable only mid-login (a pending first factor).
  def two_factor_challenge
    # Defensive: the 2FA step must never render in an authenticated context (e.g. a remember-cookie
    # re-auth). Signing out keeps MFA un-bypassable and avoids the authenticated-chrome render.
    sign_out(resource_name) if user_signed_in?
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
      # AC-7 — a failed SECOND factor never reaches Warden: we render instead of throwing, so the
      # `Warden::Manager.before_failure` hook in config/initializers/warden_audit.rb (the only other
      # place login failures are recorded) cannot see it. Without this write, wrong OTP and recovery
      # codes are COMPLETELY INVISIBLE in the audit trail — an unsuccessful-logon-attempt gap, and the
      # reason a real lockout investigation found a counter far ahead of the recorded failures.
      # `factor: second_factor` matches the discriminator the Warden hook already computes.
      AccessLog.security_event!(
        event_type: 'login_failure',
        request: request,
        user: user,
        metadata: { 'attempted_email' => user.email, 'factor' => 'second_factor' }
      )
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
    # A :lockable-locked account must not authenticate via ANY path — the password path (#create)
    # refuses locked accounts, so the passkey path must too (FedRAMP AC-7). Reject before sign-in.
    if user.access_locked?
      return render(json: { error: t('devise.failure.locked', default: 'Your account is locked.') },
                    status: :unprocessable_entity)
    end
    # Mirror #verify_otp: a completed authentication clears any accumulated lockable counter.
    user.update_column(:failed_attempts, 0) if user.failed_attempts.to_i.positive?
    sign_in(resource_name, user)
    set_flash_message!(:notice, :signed_in)
    render json: { redirect: after_sign_in_path_for(user) }
  rescue WebAuthn::Error => e
    render json: { error: e.message }, status: :unprocessable_entity
  end

  # AC-7 — NEVER call `current_user` / `user_signed_in?` in this controller's filters.
  #
  # Devise's `current_user` is `warden.authenticate(scope: :user)`, which RUNS THE WARDEN STRATEGIES
  # whenever no user is in the session. On POST /users/sign_in the credentials are still sitting in
  # `params`, so the strategies consider themselves valid and attempt a REAL authentication. For an
  # MFA account they all fail — the OTP is not in params — and Devise :lockable increments
  # `failed_attempts` once per failing strategy. Net effect before this fix: a perfectly CORRECT
  # first-factor password silently added **+4** to the lock counter, so two clean logins tripped a
  # 5-attempt threshold and locked the user out. Non-MFA accounts authenticate successfully in that
  # same call, which is why only MFA users were affected. Worse, `warden.authenticate` does not
  # `throw(:warden)`, so the before_failure audit hook never fired and the increments were invisible.
  #
  # `warden.authenticated?` reads the SESSION only (Warden::Proxy#user -> session_serializer.fetch)
  # and never runs a strategy, so it is the safe way to ask "is someone already signed in?" here.
  # It still sees a user established earlier in THIS request (Devise's sign_in populates warden),
  # so the post-login Visit row and whodunnit backfill keep working.
  def session_user
    warden.authenticated?(:user) ? warden.user(:user) : nil
  end
  helper_method :session_user

  # PaperTrail's `set_paper_trail_whodunnit` before_action (ApplicationController) calls this, and
  # its DEFAULT implementation is `current_user` — another strategy trigger on the sign-in POST.
  # PasswordsController already overrides it for the same reason.
  def user_for_paper_trail
    session_user&.id
  end

  def set_whodunnit
    actor = session_user
    return unless actor

    PaperTrail::Version.where(item_id: actor.id, whodunnit: nil).each do |v|
      v.update(whodunnit: actor.id)
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
    Visit.create(user: session_user)
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
