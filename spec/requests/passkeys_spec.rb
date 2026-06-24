require 'rails_helper'
require 'webauthn/fake_client'

# Phase 2 — WebAuthn passkey REGISTRATION (FedRAMP IA-2). Drives the ceremony end-to-end with
# WebAuthn::FakeClient (server-side verification only — the real browser navigator.credentials API and
# the secure-context requirement are out of suite scope and covered by the user's manual browser test).
RSpec.describe 'Passkey registration + management', type: :request do
  include Devise::Test::IntegrationHelpers

  # The controller derives origin/RP-id from request.host. Request specs default to the host
  # www.example.com over http; we bind the FakeClient to that SAME origin so the attestation verifies.
  # (A tenant-subdomain host like cases.example.com would make Apartment switch to a non-existent test
  # schema -> 500; the default host resolves to the seeded test tenant.)
  let(:origin) { 'http://www.example.com' }
  # The controller derives the RP id as the registrable domain (last two labels) of request.host —
  # www.example.com -> example.com. FakeClient must sign against the SAME RP id or verification fails
  # with RpIdVerificationError.
  let(:rp_id)  { 'example.com' }
  let(:password) { 'SecurePass123!' }
  let(:user)   { create(:user, password: password, password_confirmation: password) }

  def fake_client
    @fake_client ||= WebAuthn::FakeClient.new(origin)
  end

  describe 'POST /passkeys/options (registration options)' do
    it 'requires authentication' do
      post passkey_registration_options_path
      expect(response).to redirect_to(new_user_session_path)
    end

    it 'returns creation options JSON and stashes the challenge for a signed-in user' do
      sign_in user
      post passkey_registration_options_path
      expect(response).to have_http_status(:ok)
      body = JSON.parse(response.body)
      expect(body['challenge']).to be_present
      expect(body['user']).to be_present
      expect(body['rp']).to be_present
      expect(session[:webauthn_registration_challenge]).to be_present
      expect(user.reload.webauthn_id).to be_present # populated lazily on first options call
    end
  end

  describe 'POST /passkeys (registration verify, FakeClient-driven)' do
    it 'creates a credential from a valid attestation' do
      sign_in user
      post passkey_registration_options_path
      options = JSON.parse(response.body)

      attestation = fake_client.create(challenge: options['challenge'], rp_id: rp_id, user_verified: true)

      expect {
        post passkeys_path, params: {
          nickname: 'My YubiKey',
          credential: attestation
        }, as: :json
      }.to change(user.webauthn_credentials, :count).by(1)

      expect(response).to have_http_status(:ok)
      cred = user.webauthn_credentials.last
      expect(cred.nickname).to eq('My YubiKey')
      expect(cred.external_id).to eq(attestation['id'])
    end

    it 'rejects an attestation when no registration challenge is in progress' do
      sign_in user
      # No prior options call -> no stashed challenge.
      post passkeys_path, params: { credential: { id: 'x', type: 'public-key' } }, as: :json
      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.webauthn_credentials.count).to eq(0)
    end

    it 'rejects a forged attestation (wrong challenge) and creates no row' do
      sign_in user
      post passkey_registration_options_path # stashes the real challenge

      forged = fake_client.create(challenge: WebAuthn.generate_user_id, rp_id: rp_id) # different challenge
      post passkeys_path, params: { credential: forged }, as: :json

      expect(response).to have_http_status(:unprocessable_entity)
      expect(user.webauthn_credentials.count).to eq(0)
    end
  end

  describe 'GET /passkeys (management page provisions nothing destructive)' do
    it 'does not mutate existing credentials' do
      sign_in user
      create(:webauthn_credential, user: user)
      expect { get passkeys_path }.not_to change(user.webauthn_credentials, :count)
    end
  end

  describe 'DELETE /passkeys/:id' do
    it 'removes the credential' do
      sign_in user
      cred = create(:webauthn_credential, user: user)
      expect { delete passkey_path(cred) }.to change(user.webauthn_credentials, :count).by(-1)
    end
  end
end
