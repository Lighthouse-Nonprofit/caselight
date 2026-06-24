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

  describe 'login strategy' do
    it 'a user without MFA signs in with email + password' do
      post user_session_path, params: { user: { email: plain_user.email, password: password } }
      expect(authenticated?).to be true
    end

    it 'an MFA user CANNOT sign in with the password alone (no bypass)' do
      post user_session_path, params: { user: { email: mfa_user.email, password: password } }
      expect(authenticated?).to be false
    end

    it 'an MFA user CANNOT sign in with a wrong code' do
      post user_session_path, params: { user: { email: mfa_user.email, password: password, otp_attempt: '000000' } }
      expect(authenticated?).to be false
    end

    it 'an MFA user signs in with password + a valid TOTP code' do
      code = ROTP::TOTP.new(mfa_user.otp_secret).now
      post user_session_path, params: { user: { email: mfa_user.email, password: password, otp_attempt: code } }
      expect(authenticated?).to be true
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
