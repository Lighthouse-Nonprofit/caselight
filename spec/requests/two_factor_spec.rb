require 'rails_helper'

# Phase 2 Step 6 — TOTP MFA. Verifies the login strategy (no password-only bypass once enabled),
# OTP-gated sign-in, and self-service enrollment. FedRAMP IA-2(1).
RSpec.describe 'Two-factor authentication (MFA)', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { 'SecurePass123!' }
  let(:plain_user) { create(:user, password: password, password_confirmation: password) }
  let(:mfa_user) do
    create(:user, password: password, password_confirmation: password).tap do |u|
      u.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: true)
    end
  end

  # A protected page bounces unauthenticated requests to the login page (cf. large_request_spec),
  # so this is a reliable "am I signed in?" probe across the shared request-spec session.
  def authenticated?
    get '/dashboards'
    !(response.redirect? && response.location.to_s.include?('/users/sign_in'))
  end

  it 'uses the two-factor devise modules' do
    expect(User.devise_modules).to include(:two_factor_authenticatable, :two_factor_backupable)
  end

  # NB: the "not signed in" cases assert on the immediate response + session (per-request, leak-free)
  # rather than the cross-request `authenticated?` probe — under Devise's warden test-mode a prior
  # example's sign-in can leak into a later GET and spuriously read as authenticated. The deferral
  # (302 -> /users/two_factor with a pending id, but no warden session) is the precise contract here.
  describe 'login (two-step for MFA accounts)' do
    it 'a user without MFA signs in with email + password in one step' do
      post user_session_path, params: { user: { email: plain_user.email, password: password } }
      expect(authenticated?).to be true
    end

    it 'a correct password for an MFA account defers to the OTP screen (no session granted yet)' do
      post user_session_path, params: { user: { email: mfa_user.email, password: password } }
      expect(response.location).to include('/users/two_factor')
      expect(session[:otp_pending_user_id]).to eq(mfa_user.id)
    end

    it 'an OTP sent with the password (old combined form) is ignored — still only deferred' do
      code = ROTP::TOTP.new(mfa_user.otp_secret).now
      post user_session_path, params: { user: { email: mfa_user.email, password: password, otp_attempt: code } }
      expect(response.location).to include('/users/two_factor')
      expect(session[:otp_pending_user_id]).to eq(mfa_user.id)
    end

    it 'a wrong password for an MFA account fails the first factor (no OTP screen, no pending state)' do
      post user_session_path, params: { user: { email: mfa_user.email, password: 'WrongPass123!' } }
      expect(response.location.to_s).not_to include('/users/two_factor')
      expect(session[:otp_pending_user_id]).to be_nil
    end

    it 'the OTP screen is unusable without a pending first factor' do
      post verify_two_factor_path, params: { otp_attempt: '123456' }
      expect(response.location).to include('/users/sign_in')
    end

    # REGRESSION — THE production lockout (2026-09-08). `set_whodunnit`/`increase_visit_count` called
    # Devise's `current_user`/`user_signed_in?`, i.e. `warden.authenticate`, which runs the Warden
    # STRATEGIES when the session has no user. On this POST the credentials are still in params, so
    # the strategies re-attempted the login and FAILED for MFA accounts (no OTP in params) —
    # incrementing :lockable's counter once per failing strategy. A correct password added +4, so the
    # SECOND clean login crossed OCA's 5-attempt threshold and locked real staff out, silently (the
    # non-bang authenticate never throws, so the before_failure audit hook saw nothing).
    describe 'lock counter hygiene on the first factor' do
      it 'a CORRECT password leaves failed_attempts untouched' do
        mfa_user.update_columns(failed_attempts: 0, locked_at: nil)

        expect {
          post user_session_path, params: { user: { email: mfa_user.email, password: password } }
        }.not_to change { mfa_user.reload.failed_attempts }.from(0)

        expect(response.location).to include('/users/two_factor')
      end

      it 'repeated correct-password logins never accumulate toward a lockout' do
        mfa_user.update_columns(failed_attempts: 0, locked_at: nil)

        (User.maximum_attempts + 2).times do
          post user_session_path, params: { user: { email: mfa_user.email, password: password } }
        end

        mfa_user.reload
        expect(mfa_user.failed_attempts).to eq(0)
        expect(mfa_user.access_locked?).to be false
      end

      # Brute-force protection must still bite. NB the cost of one wrong password is 2, not 1: this
      # model registers TWO authenticating strategies (:two_factor_backupable and
      # :two_factor_authenticatable) and each runs `valid_for_authentication?`, so each increments.
      # That is upstream devise-two-factor behaviour, identical for non-MFA accounts, and it means
      # the EFFECTIVE lockout threshold is half the configured `lockout_max_attempts`. Pinned here
      # so a change to the strategy list (or an upstream fix) is caught rather than silently
      # halving/doubling how many typos it takes to lock a real user out.
      it 'a WRONG password still counts toward the lockout' do
        mfa_user.update_columns(failed_attempts: 0, locked_at: nil)

        expect {
          post user_session_path, params: { user: { email: mfa_user.email, password: 'WrongPass123!' } }
        }.to change { mfa_user.reload.failed_attempts }.from(0).to(2)
      end
    end

    # REGRESSION (production lockout, 2026-09-08). The MFA branch validates the password with a bare
    # `valid_password?`, bypassing Devise's `valid_for_authentication?` -- which is also where Devise
    # clears an EXPIRED lock (`unlock_access! if lock_expired?`). Without the explicit cleanup in
    # SessionsController#create, an expired lock left `locked_at` set and `failed_attempts` stranded
    # at/over the threshold, so the next single typo re-locked the account immediately, over and over.
    context 'when a previous lock has expired' do
      let(:expired_lock_user) do
        mfa_user.tap do |u|
          u.update_columns(failed_attempts: User.maximum_attempts + 3,
                           locked_at: (User.unlock_in + 5.minutes).ago)
        end
      end

      it 'clears the stale lock and the accumulated counter on the next sign-in' do
        expect(expired_lock_user.access_locked?).to be false # window elapsed, but state lingers

        post user_session_path, params: { user: { email: expired_lock_user.email, password: password } }

        expired_lock_user.reload
        expect(expired_lock_user.locked_at).to be_nil
        expect(expired_lock_user.failed_attempts).to eq(0)
        expect(response.location).to include('/users/two_factor')
      end

      it 'so a single later mistyped password does NOT re-lock the account' do
        post user_session_path, params: { user: { email: expired_lock_user.email, password: password } }
        post user_session_path, params: { user: { email: expired_lock_user.email, password: 'WrongPass123!' } }

        # Counting restarts from zero (2 = one typo, see the strategy-count note above) instead of
        # resuming from the stranded pre-lock total, which is what used to re-lock instantly.
        expired_lock_user.reload
        expect(expired_lock_user.failed_attempts).to eq(2)
        expect(expired_lock_user.access_locked?).to be false
      end
    end

    # The lock itself must still bite while it is live -- the fix clears EXPIRED locks only.
    it 'still refuses the OTP screen while a lock is genuinely active' do
      mfa_user.update_columns(failed_attempts: User.maximum_attempts, locked_at: Time.current)

      post user_session_path, params: { user: { email: mfa_user.email, password: password } }

      expect(response.location.to_s).not_to include('/users/two_factor')
      expect(session[:otp_pending_user_id]).to be_nil
      expect(mfa_user.reload.access_locked?).to be true
    end

    it 'never leaves a lingering session authenticated on the 2FA step (no remember-cookie bypass)' do
      # Simulate an already-authenticated session reaching the 2FA step (e.g. a remember-cookie
      # re-auth). The step must sign it out, not render the authenticated chrome / let MFA be skipped.
      sign_in mfa_user
      get two_factor_challenge_path
      expect(authenticated?).to be false
    end

    context 'after a correct first factor (password) for an MFA account' do
      before { post user_session_path, params: { user: { email: mfa_user.email, password: password } } }

      it 'completes sign-in with a valid TOTP code' do
        code = ROTP::TOTP.new(mfa_user.otp_secret).now
        post verify_two_factor_path, params: { otp_attempt: code }
        expect(session[:otp_pending_user_id]).to be_nil   # consumed
        expect(authenticated?).to be true
      end

      it 'rejects a wrong code — stays on the OTP step, still pending, not signed in' do
        post verify_two_factor_path, params: { otp_attempt: '000000' }
        expect(response).to have_http_status(:unprocessable_entity)
        expect(session[:otp_pending_user_id]).to eq(mfa_user.id)
      end

      it 'completes sign-in with a one-time recovery code' do
        recovery = mfa_user.generate_otp_backup_codes!
        mfa_user.save!
        post verify_two_factor_path, params: { otp_attempt: recovery.first }
        expect(session[:otp_pending_user_id]).to be_nil
        expect(authenticated?).to be true
      end
    end
  end

  describe 'enrollment' do
    # NB: the full enrollment PAGE render is left for the user's browser test — the authenticated app
    # layout needs a live tenant/Organization.current that this request-spec context doesn't set up
    # (the suite has no authenticated app-page render specs). Here we lock in the exact QR path the
    # controller uses (provisioning URI + inline SVG) without the HTTP layout.
    it 'builds a scannable provisioning URI + inline QR for enrollment' do
      user = create(:user).tap { |u| u.update!(otp_secret: User.generate_otp_secret) }
      uri  = user.otp_provisioning_uri("CaseLight (#{user.email})", issuer: 'CaseLight')
      expect(uri).to start_with('otpauth://totp/')

      svg = RQRCode::QRCode.new(uri).as_svg(module_size: 4, use_path: true, viewbox: true)
      expect(svg).to include('<svg')
    end

    it 'provisions an OTP secret when the enrollment page is opened' do
      sign_in plain_user
      get two_factor_settings_path
      # (response render may need a live tenant; the side effect — provisioning the secret — runs first)
      expect(plain_user.reload.otp_secret).to be_present
    end

    it 'enables MFA and issues recovery codes when a valid code is submitted' do
      sign_in plain_user
      plain_user.update!(otp_secret: User.generate_otp_secret)
      code = ROTP::TOTP.new(plain_user.otp_secret).now

      post two_factor_settings_path, params: { otp_attempt: code }

      plain_user.reload
      expect(plain_user.otp_required_for_login).to be true
      expect(plain_user.otp_backup_codes).to be_present
    end

    it 'rejects enrollment with an invalid code' do
      sign_in plain_user
      plain_user.update!(otp_secret: User.generate_otp_secret)

      post two_factor_settings_path, params: { otp_attempt: '000000' }

      expect(plain_user.reload.otp_required_for_login).to be false
    end
  end
end
