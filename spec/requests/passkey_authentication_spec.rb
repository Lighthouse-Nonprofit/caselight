require 'rails_helper'
require 'webauthn/fake_client'

# Phase 2 — passwordless passkey LOGIN (FedRAMP IA-2). Drives the full authentication ceremony with
# WebAuthn::FakeClient: register a credential through the real registration endpoints, then sign in
# with navigator.credentials.get-equivalent assertions. Asserts the passkey signs the user in WITHOUT
# the separate TOTP step (a user-verifying passkey is itself multi-factor) and that tampered/replayed
# assertions are rejected. The real browser API + secure-context requirement are out of suite scope.
RSpec.describe 'Passwordless passkey authentication', type: :request do
  include Devise::Test::IntegrationHelpers

  # Bind the FakeClient to the request-spec default origin (see passkeys_spec for why not a subdomain).
  # The controller derives RP id = registrable domain of request.host (www.example.com -> example.com).
  let(:origin) { 'http://www.example.com' }
  let(:rp_id)  { 'example.com' }
  let(:password) { 'SecurePass123!' }
  let(:user)   { create(:user, password: password, password_confirmation: password) }

  def fake_client
    @fake_client ||= WebAuthn::FakeClient.new(origin)
  end

  # A protected page bounces unauthenticated requests to login (cf. two_factor_spec) — a reliable
  # "am I signed in?" probe across the shared request-spec session.
  def authenticated?
    get '/dashboards'
    !(response.redirect? && response.location.to_s.include?('/users/sign_in'))
  end

  # Register a real credential for `user` via the signed-in registration ceremony, then sign back out
  # so the login ceremony starts from an unauthenticated session. Returns nothing; the credential is
  # persisted and bound to fake_client.
  def register_credential!
    sign_in user
    post passkey_registration_options_path
    options = JSON.parse(response.body)
    attestation = fake_client.create(challenge: options['challenge'], rp_id: rp_id, user_verified: true)
    post passkeys_path, params: { credential: attestation }, as: :json
    expect(response).to have_http_status(:ok)
    sign_out user
  end

  describe 'POST /users/passkey/options' do
    it 'returns authentication options JSON and stashes the challenge' do
      post passkey_login_options_path
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['challenge']).to be_present
      expect(session[:webauthn_authentication_challenge]).to be_present
    end
  end

  describe 'POST /users/passkey/callback (passwordless sign-in)' do
    it 'signs the user in with a valid assertion' do
      register_credential!

      post passkey_login_options_path, params: { email: user.email }
      options = JSON.parse(response.body)
      assertion = fake_client.get(challenge: options['challenge'], rp_id: rp_id, user_verified: true)

      post passkey_login_callback_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)['redirect']).to be_present
      expect(authenticated?).to be true
    end

    it 'does NOT route through the TOTP screen even when otp_required_for_login is set' do
      register_credential!
      user.update!(otp_secret: User.generate_otp_secret, otp_required_for_login: true)

      post passkey_login_options_path, params: { email: user.email }
      options = JSON.parse(response.body)
      assertion = fake_client.get(challenge: options['challenge'], rp_id: rp_id, user_verified: true)

      post passkey_login_callback_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:ok)
      # The response is a direct sign-in redirect, never the /users/two_factor challenge.
      expect(JSON.parse(response.body)['redirect']).not_to include('/users/two_factor')
      expect(authenticated?).to be true
    end

    it 'rejects an assertion when no challenge is in progress' do
      register_credential!
      assertion = fake_client.get(challenge: WebAuthn.generate_user_id, rp_id: rp_id)
      post passkey_login_callback_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(authenticated?).to be false
    end

    it 'rejects an assertion for a credential the server does not know' do
      register_credential!          # the fake_client now holds a key pair...
      WebauthnCredential.delete_all # ...but the server has no matching row.

      post passkey_login_options_path, params: { email: user.email }
      options = JSON.parse(response.body)
      assertion = fake_client.get(challenge: options['challenge'], rp_id: rp_id, user_verified: true)

      post passkey_login_callback_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(authenticated?).to be false
    end

    it 'refuses sign-in for a :lockable-locked account (no lock bypass via passkey)' do
      register_credential!
      user.lock_access!   # Devise :lockable — same accounts the password path refuses

      post passkey_login_options_path, params: { email: user.email }
      options = JSON.parse(response.body)
      assertion = fake_client.get(challenge: options['challenge'], rp_id: rp_id, user_verified: true)

      post passkey_login_callback_path, params: { credential: assertion }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(authenticated?).to be false
    end
  end

  describe 'coexistence with the password + TOTP login' do
    it 'keeps BOTH the two-factor and (additive) passkey login wiring intact' do
      # The devise password/OTP strategy is untouched: passkeys do NOT add a devise module.
      expect(User.devise_modules).to include(:two_factor_authenticatable, :two_factor_backupable)
      # Passkeys are wired as an association, not a devise strategy.
      expect(User.reflect_on_association(:webauthn_credentials)).to be_present
    end
  end
end
