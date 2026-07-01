# frozen_string_literal: true
# Request-level proof: runtime enforcement, admin-lockout prevention (nudge-not-block, floor, 422),
# audit write, admin-only. Logs in via the app's real session form (post user_session_path) — the
# suite's DeviseTokenAuthHelpers#sign_in is an API-token helper, not a browser login.
require 'rails_helper'

RSpec.describe 'Runtime enforcement toggles', type: :request do
  PW = 'SecurePass123!'

  def make(role)
    create(:user, roles: role, password: PW, password_confirmation: PW)
  end

  def login(user)
    post user_session_path, params: { user: { email: user.email, password: PW } }
  end

  describe 'Require MFA is a NUDGE not a block — (c)' do
    it 'redirects an un-enrolled user to enroll when require_mfa ON; enroll page stays reachable' do
      EnforcementSetting.create!(require_mfa: true)
      RequestStore.clear!
      worker = make('case worker') # otp_required_for_login false
      login worker
      get root_path
      expect(response.location.to_s).to match(%r{/two_factor_settings(\?|$)}) # app appends ?locale=en
      # Reachability: the enroll page itself is NOT redirected (nudge, not block).
      get two_factor_settings_path
      expect(response).to have_http_status(:ok)
    end

    it 'lets an un-enrolled ADMIN still reach the enforcement panel to flip it back' do
      EnforcementSetting.create!(require_mfa: true)
      RequestStore.clear!
      admin_no_mfa = make('admin')
      login admin_no_mfa
      get enforcement_settings_path
      expect(response).to have_http_status(:ok) # enforcement_settings is exempted from the nudge
    end

    it 'nudges nobody when require_mfa is unset and the privileged config flag is OFF — (a)' do
      worker = make('case worker')
      login worker
      get root_path
      expect(response.location.to_s).not_to include('two_factor')
    end
  end

  describe 'Password expiry redirect-not-lockout — (b/c)' do
    it 'sends an aged user to the change-password page at next login; the page is reachable (no loop)' do
      EnforcementSetting.create!(password_max_age_days: 30)
      RequestStore.clear!
      user = make('case worker')
      user.update_column(:password_changed_at, 40.days.ago)
      login user # Warden after_authentication hook sets session['password_expired']
      get root_path
      expect(response.location.to_s).to match(%r{/users/password_expired(\?|$)}) # app appends ?locale=en
      get user_password_expired_path
      expect(response).to have_http_status(:ok) # reachable change form
    end

    it 'does NOT expire an aged user when password_max_age_days is unset — (a)' do
      user = make('case worker')
      user.update_column(:password_changed_at, 400.days.ago)
      login user
      get root_path
      expect(response).not_to redirect_to(user_password_expired_path)
    end
  end

  describe 'strong params + range validation — (c)' do
    it 're-renders (422) instead of persisting a below-floor lockout, and auth is unbricked' do
      login make('admin')
      patch enforcement_settings_path, params: { enforcement_setting: { lockout_max_attempts: '1' } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(EnforcementSetting.first&.lockout_max_attempts).to be_nil
      RequestStore.clear!
      expect(User.maximum_attempts).to eq(10) # unchanged
    end

    it 'ignores unknown keys and stores a valid override' do
      login make('admin')
      patch enforcement_settings_path, params: { enforcement_setting: { evil: 'x', idle_timeout_minutes: '15' } }
      expect(EnforcementSetting.first.idle_timeout_minutes).to eq(15)
    end
  end

  describe 'audit — (e)' do
    it 'writes an enforcement_flag_changed AccessLog with coarse metadata on a value change' do
      login make('admin')
      expect(AccessLog).to receive(:security_event!)
        .with(hash_including(event_type: 'enforcement_flag_changed')).and_call_original
      patch enforcement_settings_path, params: { enforcement_setting: { idle_timeout_minutes: '15', require_mfa: 'true' } }
    end
  end

  describe 'admin-only' do
    it 'denies a non-admin (no write occurs)' do
      login make('case worker')
      expect {
        patch enforcement_settings_path, params: { enforcement_setting: { idle_timeout_minutes: '15' } }
      }.not_to change(EnforcementSetting, :count)
      expect(response).not_to have_http_status(:ok) # CanCan denies -> 403/redirect per the app rescue
    end
  end
end
