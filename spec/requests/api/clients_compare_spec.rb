# frozen_string_literal: true
require 'rails_helper'

# api/clients#compare (POAM-AC3-COMPARE) — the cross-tenant duplicate-detection endpoint. It is the
# ONE action that authorizes DIFFERENTLY: `skip_authorization_check only: [:compare]` (no record-level
# CanCan authorize), then iterates `Organization.without_demo`, `switch_to`s each tenant, runs
# `Client.filter(params)`, labels the hits with the org's full_name, and serializes each through
# ClientSerializer with a PER-TENANT-RECOMPUTED sensitive-field/domain view (break_glass: [], record-less).
#
# Isolation here does NOT come from CanCan — it comes from the memo reset at clients_controller.rb:27-28
# (`@visible_custom_field_ids = nil; @visible_domain_levels = nil`) so tenant A's visible-id Set can never
# carry into tenant B. Custom-field ids are per-schema, so a *dropped* reset would over-expose tenant B's
# same-id-but-restricted form/domain with tenant A's stale Set — a silent cross-tenant leak. This suite is
# the first request/controller-flow coverage of that contract: cross-org aggregation + org labelling,
# demo-tenant exclusion, the per-tenant memo reset, restricted/emergency masking in the ACTUAL JSON, the
# find_client_by param guard, and the accepted skip_authorization_check residual.
#
# TENANTS: real ros-apartment schemas are built with Organization.create_and_build_tanent (as in
# organization_spec / the before(:suite) 'app' tenant). DatabaseCleaner's :transaction strategy rolls the
# schema DDL back per-example (PostgreSQL DDL is transactional), so fixed short_names are safe. Every
# request is authenticated in the 'app' tenant (the default host does not elevate a subdomain), so
# get_compare re-pins 'app' before each GET — the controller then switches tenants internally.
RSpec.describe 'API: api/clients#compare (cross-tenant duplicate detection)', type: :request do
  include Devise::Test::IntegrationHelpers

  after(:each) { ClientHistory.delete_all rescue nil }

  let(:match_given) { 'ZebadiahCompareMatch' }         # exact deterministic-encryption match (Tier 4/5)
  let(:match_dob)   { Date.new(2015, 3, 10) }           # date_of_birth stays plaintext -> EXTRACT month/year

  def get_compare(params)
    # Auth happens in the tenant current when the request STARTS; re-pin 'app' (where the signed-in user
    # lives) so a prior request that left the connection on another tenant can't 302 us to login.
    Apartment::Tenant.switch!('app')
    get '/api/clients/compare', params: params
  end

  def clients_json
    JSON.parse(response.body).fetch('clients')
  end

  def org_labels
    clients_json.map { |c| c['organization'] }
  end

  # Build a real tenant, run the block inside it (to seed tenant-local clients/forms), always return to 'app'.
  def build_org(full_name:, short_name:)
    org = Organization.create_and_build_tanent(full_name: full_name, short_name: short_name)
    Apartment::Tenant.switch!(short_name)
    yield org if block_given?
    org
  ensure
    Apartment::Tenant.switch!('app')
  end

  # A client in the CURRENT tenant that matches the shared compare query (given_name + date_of_birth).
  def matching_client(overrides = {})
    create(:client, { given_name: match_given, date_of_birth: match_dob }.merge(overrides))
  end

  # Attach one custom form + one filled property to `client` in the current tenant. Sentinel `value`
  # lands (decrypted) in the JSON iff the form is visible to the viewer.
  def attach_form(client, form_title:, sensitivity:, value:)
    cf = create(:custom_field, entity_type: 'Client', form_title: form_title,
                sensitivity: sensitivity, fields: [{ 'type' => 'text', 'label' => 'Note' }])
    create(:custom_field_property, custom_field: cf, custom_formable: client,
           properties: { 'Note' => value })
    cf
  end

  it 'returns identity matches from EVERY non-demo tenant, each labelled with its org full_name' do
    build_org(full_name: 'Alpha House',  short_name: 'alphaorg') { matching_client }
    build_org(full_name: 'Beta Center',  short_name: 'betaorg')  { matching_client }
    # 'app' (Organization Testing) is also non-demo but has no matching client -> silently skipped.

    sign_in create(:user, :admin)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(clients_json.size).to eq(2)
    expect(org_labels).to match_array(['Alpha House', 'Beta Center'])
    expect(clients_json.map { |c| c['given_name'] }).to all(eq(match_given))
  end

  it 'EXCLUDES the demo tenant (Organization.without_demo) from the results' do
    build_org(full_name: 'Alpha House', short_name: 'alphaorg') { matching_client }
    # A full_name == 'Demo' org whose client WOULD match on given_name — proves absence is exclusion, not a miss.
    build_org(full_name: 'Demo', short_name: 'demoorg') do
      matching_client(local_given_name: 'DEMOSENTINELLOCAL')
    end

    sign_in create(:user, :admin)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(org_labels).to include('Alpha House')   # non-vacuity: a real match IS returned
    expect(org_labels).not_to include('Demo')
    expect(response.body).not_to include('DEMOSENTINELLOCAL')
  end

  it 'OMITS restricted and emergency-only custom-field values for a standard-only viewer (break_glass: [])' do
    client = matching_client
    attach_form(client, form_title: 'Std Intake',  sensitivity: 'standard',       value: 'STD_CFP_VALUE')
    attach_form(client, form_title: 'Health',      sensitivity: 'restricted',     value: 'RESTRICTED_CFP_VALUE')
    attach_form(client, form_title: 'Emergency',   sensitivity: 'emergency_only', value: 'EMERGENCY_CFP_VALUE')

    sign_in create(:user, :strategic_overviewer)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('STD_CFP_VALUE')            # non-vacuity: standard values DO render
    expect(response.body).not_to include('RESTRICTED_CFP_VALUE')
    expect(response.body).not_to include('EMERGENCY_CFP_VALUE')
  end

  it 'OMITS restricted-domain CSI scores/notes from the embedded assessments for a standard-only viewer' do
    client     = matching_client(state: 'accepted')
    assessment = create(:assessment, client: client)
    dg         = create(:domain_group)
    std_domain = create(:domain, domain_group: dg, sensitivity: 'standard')
    res_domain = create(:domain, domain_group: dg, sensitivity: 'restricted')
    create(:assessment_domain, assessment: assessment, domain: std_domain, reason: 'STD_DOMAIN_REASON_X')
    create(:assessment_domain, assessment: assessment, domain: res_domain, reason: 'RESTRICTED_DOMAIN_REASON_X')

    sign_in create(:user, :strategic_overviewer)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('STD_DOMAIN_REASON_X')          # non-vacuity: standard domain renders
    expect(response.body).not_to include('RESTRICTED_DOMAIN_REASON_X')
  end

  it 'MASKS per tenant: a standard form in tenant A is present while a restricted form in tenant B is absent' do
    # Each fresh schema numbers its first custom_field id 1, so tenant A's form id COLLIDES with tenant B's.
    # A dropped `@visible_custom_field_ids = nil` reset would reuse A's Set {1} in B, leaking B's restricted
    # (id 1) form. The correct per-tenant recompute yields {} in B -> BETA_RESTRICTED_VALUE stays masked.
    build_org(full_name: 'Alpha House', short_name: 'alphaorg') do
      attach_form(matching_client, form_title: 'A Form', sensitivity: 'standard',   value: 'ALPHA_STD_VALUE')
    end
    build_org(full_name: 'Beta Center', short_name: 'betaorg') do
      attach_form(matching_client, form_title: 'B Form', sensitivity: 'restricted', value: 'BETA_RESTRICTED_VALUE')
    end

    sign_in create(:user, :strategic_overviewer)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    # Both tenants matched -> the Beta entry EXISTS (its value is masked, not the whole record dropped).
    expect(org_labels).to match_array(['Alpha House', 'Beta Center'])
    expect(response.body).to include('ALPHA_STD_VALUE')             # visible standard form in tenant A
    expect(response.body).not_to include('BETA_RESTRICTED_VALUE')   # masked restricted form in tenant B (memo reset holds)
  end

  it 'returns [] for a village/commune-only request but MATCHES on given_name (find_client_by guard)' do
    matching_client(village: 'RiversideVillage', commune: 'RiversideCommune')

    sign_in create(:user, :admin)

    # village/commune are NOT in the find_client_by allow-list -> filter is never run -> [] for every org.
    get_compare(village: 'RiversideVillage', commune: 'RiversideCommune')
    expect(response).to have_http_status(:ok)
    expect(clients_json).to eq([])

    # The same client IS reachable through an allow-listed identity param.
    get_compare(given_name: match_given)
    expect(response).to have_http_status(:ok)
    expect(clients_json).not_to be_empty
    expect(clients_json.first['given_name']).to eq(match_given)
  end

  it 'is reachable by a signed-in NON-ADMIN without a per-record authorize, exposing identity fields (POAM-AC3-COMPARE residual)' do
    matching_client   # its caseload user is the factory user, NOT the viewer below

    worker = create(:user, :case_worker)   # a non-admin, off this client's caseload
    sign_in worker
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    # Documents the accepted residual: any signed-in user can confirm an identity match in any tenant,
    # with no record-level authorize — the masking (examples 3-5) limits this to non-sensitive fields.
    expect(response).to have_http_status(:ok)
    expect(clients_json).not_to be_empty
    entry = clients_json.first
    expect(entry['given_name']).to eq(match_given)   # identity field exposed
    expect(entry['additional_form']).to eq([])       # no custom-form data attached -> none leaked
  end
end
