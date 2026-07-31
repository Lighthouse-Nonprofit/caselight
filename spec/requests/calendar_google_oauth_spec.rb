# frozen_string_literal: true
require 'rails_helper'

# Data-task batch C5 — the rebuilt Google OAuth surface (connect/callback/disconnect).
# Pins the security contract:
#   * dormant install (no creds) => connect bounces with an alert, no redirect to Google
#   * callback verifies the session `state` (anti-CSRF) before touching the code
#   * a good exchange stores the refresh token ENCRYPTED on current_user; disconnect clears it
#   * strategic overviewer (no Task grant) is 403'd — the actions authorize :update, Task
RSpec.describe 'Google Calendar OAuth (rebuilt push)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:worker)   { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def stub_google_env(id, secret)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return(id)
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return(secret)
  end

  it 'requires authentication' do
    get google_auth_calendars_path
    expect(response).to have_http_status(:found)
    expect(response.headers['Location']).to include('/users/sign_in')
  end

  context 'dormant install (no Google credentials)' do
    before do
      stub_google_env(nil, nil)
      sign_in_as(worker)
    end

    it 'bounces connect back to the calendar with an alert, never to Google' do
      get google_auth_calendars_path
      # rendered redirects carry ?locale=en (default_url_options) — match loosely
      expect(response.headers['Location']).to match(%r{/calendars(\?locale=en)?\z})
      expect(flash[:alert]).to include('not configured')
    end
  end

  context 'enabled install' do
    before do
      stub_google_env('cid', 'secret')
      sign_in_as(worker)
    end

    it 'redirects connect to Google with a state param and remembers it in the session' do
      get google_auth_calendars_path
      expect(response).to have_http_status(:found)
      expect(response.headers['Location']).to start_with('https://accounts.google.com/o/oauth2/auth')
      expect(response.headers['Location']).to include('state=')
      expect(session[:google_oauth_state]).to be_present
      expect(response.headers['Location']).to include(session[:google_oauth_state])
    end

    it 'rejects a callback whose state does not match the session (anti-CSRF)' do
      get google_auth_calendars_path # seeds session state
      expect(GoogleCalendarPush).not_to receive(:exchange_code)

      get google_callback_calendars_path, params: { state: 'forged', code: 'evil' }

      expect(response.headers['Location']).to match(%r{/calendars(\?locale=en)?\z})
      expect(flash[:alert]).to include('could not be verified')
      expect(worker.reload.google_refresh_token).to be_nil
    end

    it 'rejects a callback with no seeded session state (cold replay)' do
      expect(GoogleCalendarPush).not_to receive(:exchange_code)
      get google_callback_calendars_path, params: { state: 'anything', code: 'evil' }
      expect(response.headers['Location']).to match(%r{/calendars(\?locale=en)?\z})
      expect(flash[:alert]).to include('could not be verified')
    end

    it 'stores the refresh token encrypted on a good callback and clears it on disconnect' do
      get google_auth_calendars_path
      state = session[:google_oauth_state]
      allow(GoogleCalendarPush).to receive(:exchange_code)
        .with('good-code', redirect_uri: google_callback_calendars_url(locale: nil))
        .and_return('refresh-token-sentinel')

      get google_callback_calendars_path, params: { state: state, code: 'good-code' }

      expect(response.headers['Location']).to match(%r{/calendars(\?locale=en)?\z})
      expect(worker.reload.google_refresh_token).to eq('refresh-token-sentinel')
      # encrypted at rest: the raw column value is an AR-encryption envelope, not the token
      raw = User.connection.select_value(
        User.sanitize_sql(['SELECT google_refresh_token FROM users WHERE id = ?', worker.id])
      )
      expect(raw).to be_present
      expect(raw).not_to include('refresh-token-sentinel')

      delete google_disconnect_calendars_path
      expect(worker.reload.google_refresh_token).to be_nil
    end

    it 'consumes the state — a replayed callback fails even with the old state' do
      get google_auth_calendars_path
      state = session[:google_oauth_state]
      allow(GoogleCalendarPush).to receive(:exchange_code).and_return('tok')

      get google_callback_calendars_path, params: { state: state, code: 'good-code' }
      get google_callback_calendars_path, params: { state: state, code: 'good-code' }

      expect(flash[:alert]).to include('could not be verified')
    end
  end

  context 'as a strategic overviewer (no Task grant)' do
    let(:overviewer) do
      create(:user, roles: 'strategic overviewer', password: password, password_confirmation: password)
    end

    before do
      stub_google_env('cid', 'secret')
      sign_in_as(overviewer)
    end

    it 'is denied the connect action' do
      get google_auth_calendars_path
      expect(response).not_to have_http_status(:ok)
      expect(response.headers['Location'].to_s).not_to include('accounts.google.com')
    end
  end
end
