# frozen_string_literal: true
require 'rails_helper'

# POAM-AC3-COMPARE (closed 2026-07-26) — api/clients#compare was the ONE live cross-tenant read
# path (skip_authorization_check + an Organization.without_demo/switch_to loop returning per-org
# ClientSerializer payloads). It is now CURRENT-TENANT-ONLY with a minimal {id, organization}
# payload; this file pins the isolation end-to-end: an identity twin in another tenant is
# INVISIBLE to a tenant-'app' viewer, and unauthenticated probes are rejected. (The payload /
# name-guard / audit contracts live in spec/requests/api/clients_compare_spec.rb.)
#
# Setup mirrors organization_spec: every example runs in the 'app' tenant; the second tenant is
# built in-transaction via Organization.create_and_build_tanent and rolls back with the example.
RSpec.describe 'api/clients#compare tenant isolation (POAM-AC3-COMPARE closed)', type: :request do
  include Devise::Test::IntegrationHelpers

  B_ORG_NAME = 'Tenant B Org'

  after(:each) { ClientHistory.delete_all rescue nil }

  def within_tenant_b
    Organization.create_and_build_tanent(short_name: 'tenant-b', full_name: B_ORG_NAME)
    Apartment::Tenant.switch!('tenant-b')
    yield
  ensure
    Apartment::Tenant.switch!('app')
  end

  def get_compare(params)
    Apartment::Tenant.switch!('app')
    get compare_api_clients_path, params: params
  end

  def clients_json
    JSON.parse(response.body).fetch('clients')
  end

  it 'does NOT surface an identity twin that lives in another tenant' do
    within_tenant_b { create(:client, given_name: 'CrossTenantTwin') }

    sign_in create(:user, :admin)
    get_compare(given_name: 'CrossTenantTwin')

    expect(response).to have_http_status(:ok)
    expect(clients_json).to eq([])
    expect(response.body).not_to include(B_ORG_NAME)
  end

  it 'still finds the twin inside the request tenant (non-vacuity)' do
    local = create(:client, given_name: 'CrossTenantTwin')
    within_tenant_b { create(:client, given_name: 'CrossTenantTwin') }

    sign_in create(:user, :admin)
    get_compare(given_name: 'CrossTenantTwin')

    expect(response).to have_http_status(:ok)
    expect(clients_json.map { |c| c['id'] }).to eq([local.id])
  end

  it 'rejects an unauthenticated probe' do
    Apartment::Tenant.switch!('app')
    get compare_api_clients_path, params: { given_name: 'CrossTenantTwin' }

    expect(response).not_to have_http_status(:ok) # devise authenticate_user! bounces it
    expect(response.body).not_to include('clients')
  end
end
