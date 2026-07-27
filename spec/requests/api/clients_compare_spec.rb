# frozen_string_literal: true
require 'rails_helper'

# api/clients#compare — duplicate detection behind the client form's save button.
# POAM-AC3-COMPARE (closed 2026-07-26): the endpoint is CURRENT-TENANT-ONLY (the Phase-5-era
# Organization.without_demo/switch_to loop is gone), returns the MINIMAL payload the JS consumer
# reads ({id, organization} — never record values, so there is nothing for sensitivity masking to
# mask), requires a NAME field (DOB/province only narrow a name match, never sufficient alone),
# and writes a values-free client_compare_probe AccessLog per probe.
#
# skip_authorization_check remains DELIBERATE: warning that a duplicate exists must not require
# per-record :read on the duplicate — acceptable exactly because the response carries no values.
#
# TENANTS: real ros-apartment schemas via Organization.create_and_build_tanent (transactional DDL
# rolls back per example). Requests authenticate in the 'app' tenant.
RSpec.describe 'API: api/clients#compare (current-tenant duplicate detection)', type: :request do
  include Devise::Test::IntegrationHelpers

  after(:each) do
    ClientHistory.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
  end

  let(:match_given) { 'ZebadiahCompareMatch' }  # exact deterministic-encryption match (Tier 4)
  let(:match_dob)   { Date.new(2015, 3, 10) }   # date_of_birth stays plaintext -> EXTRACT month/year

  def get_compare(params)
    Apartment::Tenant.switch!('app')
    get '/api/clients/compare', params: params
  end

  def clients_json
    JSON.parse(response.body).fetch('clients')
  end

  # Build a real tenant, run the block inside it, always return to 'app'.
  def build_org(full_name:, short_name:)
    org = Organization.create_and_build_tanent(full_name: full_name, short_name: short_name)
    Apartment::Tenant.switch!(short_name)
    yield org if block_given?
    org
  ensure
    Apartment::Tenant.switch!('app')
  end

  def matching_client(overrides = {})
    create(:client, { given_name: match_given, date_of_birth: match_dob }.merge(overrides))
  end

  it 'matches ONLY in the current tenant and labels hits with the current org full_name' do
    local = matching_client                                            # in 'app'
    build_org(full_name: 'Alpha House', short_name: 'alphaorg') { matching_client } # elsewhere

    sign_in create(:user, :admin)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(clients_json.size).to eq(1)                                 # the alphaorg twin is NOT returned
    expect(clients_json.first['id']).to eq(local.id)
    expect(clients_json.first['organization']).to eq(Organization.find_by(short_name: 'app').full_name)
    expect(response.body).not_to include('Alpha House')
  end

  it 'does not switch the connection off the request tenant (no cross-tenant loop left)' do
    matching_client
    sign_in create(:user, :admin)
    get_compare(given_name: match_given)

    expect(response).to have_http_status(:ok)
    expect(Apartment::Tenant.current).to eq('app')
  end

  it 'returns the MINIMAL payload — exactly id + organization, never record values' do
    client = matching_client(village: 'RiversideVillage')
    cf = create(:custom_field, entity_type: 'Client', form_title: 'Health Intake',
                sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Note' }])
    create(:custom_field_property, custom_field: cf, custom_formable: client,
           properties: { 'Note' => 'CFP_SENTINEL_VALUE' })

    sign_in create(:user, :admin)
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(clients_json.first.keys).to match_array(%w[id organization])
    expect(response.body).not_to include(match_given)          # not even the probed name echoes back
    expect(response.body).not_to include('RiversideVillage')
    expect(response.body).not_to include('CFP_SENTINEL_VALUE')
    expect(response.body).not_to include(match_dob.to_s)
  end

  it 'requires a NAME field: DOB-only and province-only probes return [] (no enumeration vector)' do
    province = create(:province)
    matching_client(birth_province_id: province.id)

    sign_in create(:user, :admin)

    get_compare(date_of_birth: match_dob.to_s)
    expect(clients_json).to eq([])

    get_compare(birth_province_id: province.id)
    expect(clients_json).to eq([])

    get_compare(village: 'RiversideVillage', commune: 'RiversideCommune')
    expect(clients_json).to eq([])

    # The same client IS reachable through a name field, with DOB as a narrowing clause.
    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)
    expect(clients_json).not_to be_empty
  end

  it 'writes a values-free client_compare_probe AccessLog for every probe' do
    matching_client
    sign_in create(:user, :admin)
    get_compare(given_name: match_given)

    log = AccessLog.unscoped.where(event_type: 'client_compare_probe').last
    expect(log).to be_present
    expect(log.metadata['surface']).to eq('client_duplicate_check')
    expect(log.metadata['matches']).to eq(1)
    expect(log.attributes.to_s).not_to include(match_given)  # values-free: the probed name never lands
  end

  it 'stays reachable by a signed-in non-admin off the caseload — now harmless (no values in the payload)' do
    matching_client                       # caseload user is the factory user, NOT the viewer below
    worker = create(:user, :case_worker)
    sign_in worker

    get_compare(given_name: match_given, date_of_birth: match_dob.to_s)

    expect(response).to have_http_status(:ok)
    expect(clients_json).not_to be_empty
    expect(clients_json.first.keys).to match_array(%w[id organization])
  end
end
