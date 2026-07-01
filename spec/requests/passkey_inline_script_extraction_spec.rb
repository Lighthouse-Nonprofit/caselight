# frozen_string_literal: true
require 'rails_helper'

# Frontend Roadmap Unit 5 regression guard. The two WebAuthn passkey ceremonies (LOGIN on the
# Devise sign-in page, REGISTRATION on passkeys/show) were moved out of inline `:javascript` HAML
# blocks into Sprockets assets (app/assets/javascripts/sessions/new_passkey.js and passkeys/show.js)
# so the CSP can eventually be flipped from report-only to enforced (unit 18). These are REQUEST
# specs (no JS execution) so they run in the js-excluding CI subset. They assert the pages still
# render 200, still ship a JS asset, and no longer contain the inline ceremony script.
#
# NOTE: the WebAuthn ceremonies themselves cannot be validated in CI (they need a real secure-context
# browser + authenticator). Those are covered by the mandatory manual browser test in the PR body.
RSpec.describe 'Passkey inline-script extraction (CSP-reduction, roadmap unit 5)', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:password) { 'SecurePass123!' }

  describe 'GET new_user_session_path (Devise sign-in page)' do
    it 'renders 200, ships a JS asset, and contains no inline login ceremony' do
      get new_user_session_path
      expect(response).to have_http_status(:ok)
      body = response.body

      # The passkey login button + its hidden container still render (markup stays in HAML).
      # HAML's default attr_wrapper is a single quote, so match either quote style.
      expect(body).to match(/id=['"]passkey-login['"]/)
      expect(body).to match(/id=['"]passkey-login-area['"]/)
      # The route paths are now carried on data-* attributes (read by the extracted JS), not
      # interpolated into an inline <script>.
      expect(body).to include('data-options-url')
      expect(body).to include('data-callback-url')
      # A JS asset is included. Relaxed vs a bundle-name match so it holds under both the
      # fingerprinted single-bundle output and Sprockets debug-split per-file output.
      expect(body).to match(%r{<script[^>]*src=["'][^"']*/assets/[^"']*\.js})
      # No inline WebAuthn ceremony remains on the page (the load-bearing assertions).
      expect(body).not_to include('navigator.credentials')
      expect(body).not_to include('PublicKeyCredential')
    end
  end

  describe 'GET passkeys_path (passkeys#show, authenticated)' do
    it 'renders 200, ships a JS asset, and contains no inline registration ceremony' do
      user = create(:user, password: password, password_confirmation: password)
      sign_in user
      get passkeys_path
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to match(/id=['"]passkey-register['"]/)
      expect(body).to match(/id=['"]passkey-register-area['"]/)
      expect(body).to include('data-options-url')
      expect(body).to include('data-passkeys-url')
      expect(body).to match(%r{<script[^>]*src=["'][^"']*/assets/[^"']*\.js})
      expect(body).not_to include('navigator.credentials')
      expect(body).not_to include('PublicKeyCredential')
    end
  end

  describe 'manifest wiring (asset requires present)' do
    it 'requires both extracted passkey ceremony files in the application manifest' do
      manifest = Rails.root.join('app/assets/javascripts/application.js').read
      expect(manifest).to include('require sessions/new_passkey')
      expect(manifest).to include('require passkeys/show')
    end
  end
end
