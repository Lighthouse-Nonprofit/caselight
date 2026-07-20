# frozen_string_literal: true
require 'rails_helper'

# TenantBoundary tripwire (FedRAMP AC-3 / SC-7, SOC 2 CC6.1) — the defense-in-depth after_action that
# catches a cross-tenant connection LEAK: the Apartment schema in effect differs from the tenant the
# request host implies. Under normal operation the elevator keeps these in sync, so the ONLY way to
# exercise the guard's decision logic is to simulate the divergence. We do that by stubbing the
# controller's own `expected_tenant_from_host` (the host-derived "expected" tenant): it is called ONLY
# inside the after_action, never by the elevator middleware, so the middleware still runs on the real
# test host (www.example.com -> no subdomain -> no switch -> Apartment stays 'app'). Driving a REAL
# mismatched host instead (e.g. cases.lvh.me) is a dead end — the elevator would try to switch to a
# schema that doesn't exist in the test DB and blow up before the controller ever runs.
#
# The neighboring phase5_safety_rails_spec only asserts the flag DEFAULT (OFF); the enforce path, the
# log-only path, the allowlist, the nil-expected exemption, and case-insensitive matching are all
# untested. This closes that gap. AccessLog (Mongo) is not transactional -> delete_all around each.
RSpec.describe 'Tenant boundary tripwire (AC-3 / SC-7)', type: :request do
  include Devise::Test::IntegrationHelpers

  before(:each) { AccessLog.delete_all; EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }
  after(:each)  { AccessLog.delete_all; EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }

  # The tenant the request actually runs in (spec_helper switches every example to 'app').
  let(:tenant) { 'app' }
  let(:admin)  { create(:user, :admin) }
  before { sign_in admin }

  # Persist the flag ON via the real per-tenant override path (what the admin control room writes), then
  # bust the memo so the next request re-reads it. With no row, enabled? falls through to config.x (OFF).
  def enforce_tenant_boundary!
    EnforcementSetting.create!(enforce_tenant_boundary: true)
    EnforcementSetting.clear_cache!
  end

  # Simulate "the host implies tenant X" for the after_action only (see file header). nil = public schema.
  def host_implies_tenant(value)
    allow_any_instance_of(ApplicationController).to receive(:expected_tenant_from_host).and_return(value)
  end

  def tenant_mismatch_logs
    AccessLog.where(event_type: 'tenant_mismatch')
  end

  describe 'enforcement ON + schema/host mismatch' do
    it 'REFUSES with 409 and a blanked body' do
      enforce_tenant_boundary!
      host_implies_tenant('otherorg') # expected='otherorg' != current='app'

      get enforcement_settings_path

      expect(response).to have_http_status(:conflict) # 409
      expect(response.body).to be_blank               # self.response_body = nil
      # the guard logs BEFORE it refuses, recording that enforcement was live
      log = tenant_mismatch_logs.last
      expect(log).to be_present
      expect(log.metadata['enforced']).to be(true)
    end
  end

  describe 'enforcement OFF + schema/host mismatch (log-only, default posture)' do
    it 'SERVES the request but writes a tenant_mismatch AccessLog recording expected/current + enforced=false' do
      # no EnforcementSetting row -> enabled? resolves to config.x default (false)
      host_implies_tenant('otherorg')

      expect {
        get enforcement_settings_path
      }.to change { tenant_mismatch_logs.count }.by(1)

      expect(response).to have_http_status(:ok) # request passed through — NOT refused

      log = tenant_mismatch_logs.last
      expect(log.metadata['expected_tenant']).to eq('otherorg')
      expect(log.metadata['current_tenant']).to eq(tenant)
      expect(log.metadata['enforced']).to be(false)
      expect(log.metadata['controller']).to eq('enforcement_settings')
      expect(log.metadata['action']).to eq('show')
    end
  end

  describe 'cross-tenant allowlist (api/clients#compare)' do
    it 'does NOT refuse or log even under a mismatch with enforcement ON' do
      enforce_tenant_boundary!       # a NON-allowlisted route would 409 here
      host_implies_tenant('otherorg')

      expect {
        get compare_api_clients_path # deliberately operates across tenants -> exempt
      }.not_to change { tenant_mismatch_logs.count }

      expect(response).not_to have_http_status(:conflict)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'nil expected tenant (public schema / landing / error pages)' do
    it 'is treated as in-bounds — no refusal, no log — even with enforcement ON' do
      enforce_tenant_boundary!
      host_implies_tenant(nil) # public schema: no tenant implied

      expect {
        get enforcement_settings_path
      }.not_to change { tenant_mismatch_logs.count }

      expect(response).to have_http_status(:ok)
    end
  end

  describe 'case-insensitive tenant matching' do
    it "treats 'App' vs 'app' as in-bounds — no refusal, no log — even with enforcement ON" do
      enforce_tenant_boundary!
      host_implies_tenant(tenant.capitalize) # 'App' vs current 'app' (the demo tenant is 'cases'; test tenant is 'app')

      expect {
        get enforcement_settings_path
      }.not_to change { tenant_mismatch_logs.count }

      expect(response).to have_http_status(:ok)
    end
  end
end
