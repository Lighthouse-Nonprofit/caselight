# frozen_string_literal: true
require 'rails_helper'

# Phase 5 capstone — ADMIN FLAG-CONTROL-ROOM (AC-3 / CM-5 / AU-2). Drives the real controller through the
# auth + audit + persistence stack. AccessLog (Mongo) is not auto-cleaned -> delete_all around each example.
RSpec.describe 'Enforcement settings control room (AC-3 / CM-5 / AU-2)', type: :request do
  include Devise::Test::IntegrationHelpers
  before(:each) { AccessLog.delete_all; EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }
  after(:each)  { AccessLog.delete_all; EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }

  describe 'default (no override) = zero behavior change' do
    it 'every predicate reads OFF with no persisted row' do
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: Rails.application.config.x.enforce_authorization == true)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_least_privilege, config_default: Rails.application.config.x.enforce_least_privilege == true)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_tenant_boundary, config_default: Rails.application.config.x.enforce_tenant_boundary == true)).to be(false)
    end
  end

  describe 'admin' do
    let(:admin) { create(:user, :admin) }
    before { sign_in admin }

    it 'sees the settings page and does NOT persist a row on a GET' do
      get enforcement_settings_path
      expect(response).to have_http_status(:ok)
      expect(EnforcementSetting.count).to eq(0)
    end

    it 'toggles a flag ON, PERSISTS it, and the predicate now reads ON' do
      patch enforcement_settings_path, params: { enforcement_setting: { enforce_authorization: 'true', enforce_least_privilege: '', enforce_tenant_boundary: '' } }
      expect(response).to have_http_status(:found)
      expect(response.location).to include(enforcement_settings_path) # app appends ?locale=en

      EnforcementSetting.clear_cache!
      expect(EnforcementSetting.first.enforce_authorization).to be(true)
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(true)
      expect(EnforcementSetting.first.enforce_least_privilege).to be_nil
      expect(EnforcementSetting.enabled?(:enforce_least_privilege, config_default: false)).to be(false)
    end

    it 'AUDITS the toggle (AU-2 enforcement_flag_changed, values-free, actor recorded)' do
      expect {
        patch enforcement_settings_path, params: { enforcement_setting: { enforce_authorization: 'true', enforce_least_privilege: '', enforce_tenant_boundary: '' } }
      }.to change { AccessLog.where(event_type: 'enforcement_flag_changed').count }.by(1)

      log = AccessLog.where(event_type: 'enforcement_flag_changed').last
      expect(log.user_id).to eq(admin.id)
      change = log.metadata['changes'].find { |c| c['flag'] == 'enforce_authorization' }
      expect(change['from']).to eq('default(off)')
      expect(change['to']).to eq('on')
      expect(log.metadata['source']).to eq('enforcement_settings_ui')
      expect(EnforcementSetting.first.updated_by_id).to eq(admin.id)
    end

    it 'a no-op submit (no change) writes NO enforcement_flag_changed event' do
      EnforcementSetting.create!(enforce_authorization: true)
      EnforcementSetting.clear_cache!
      expect {
        patch enforcement_settings_path, params: { enforcement_setting: { enforce_authorization: 'true', enforce_least_privilege: '', enforce_tenant_boundary: '' } }
      }.not_to change { AccessLog.where(event_type: 'enforcement_flag_changed').count }
    end

    # CSRF is framework-provided (AdminController protect_from_forgery :exception + the form_with token) and
    # is not reliably exercisable at the request-spec layer (allow_forgery_protection is a test-env global),
    # so it is not asserted here — the mutation path is a normal authenticated PATCH form.

    it 'stays reachable to flip back OFF with authorization enforcement persisted ON (no self-lockout)' do
      EnforcementSetting.create!(enforce_authorization: true)
      EnforcementSetting.clear_cache!
      get enforcement_settings_path
      expect(response).to have_http_status(:ok)
    end

    it 'stays reachable with least_privilege enforcement forced ON (admin unaffected by narrowing)' do
      allow(Rails.application.config.x).to receive(:enforce_least_privilege).and_return(true)
      get enforcement_settings_path
      expect(response).to have_http_status(:ok)
    end

    it 'stays reachable with tenant_boundary enforcement forced ON (in-tenant route, expected==current)' do
      allow(Rails.application.config.x).to receive(:enforce_tenant_boundary).and_return(true)
      get enforcement_settings_path
      expect(response).to have_http_status(:ok)
      expect(response).not_to have_http_status(:conflict)
    end
  end

  describe 'a non-admin (case worker)' do
    let(:worker) { create(:user, :case_worker) }
    before { sign_in worker }

    it 'is DENIED the settings page (CanCan redirect, not the control room) and the denial is audited' do
      expect {
        get enforcement_settings_path
      }.to change { AccessLog.where(event_type: 'access_denied').count }.by_at_least(1)
      # CanCan denial redirects to root_url (the app appends ?locale=en); the audited access_denied above is
      # the security proof. Assert it redirected AWAY (not the 200 control room).
      expect(response).to have_http_status(:found)
    end

    it 'CANNOT toggle a flag — no row written, no enforcement_flag_changed audit' do
      expect {
        patch enforcement_settings_path, params: { enforcement_setting: { enforce_authorization: 'true' } }
      }.not_to change { AccessLog.where(event_type: 'enforcement_flag_changed').count }
      expect(EnforcementSetting.where(enforce_authorization: true).count).to eq(0)
    end
  end
end
