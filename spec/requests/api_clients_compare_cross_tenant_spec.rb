# frozen_string_literal: true
require 'rails_helper'

# POAM-AC3-COMPARE — api/clients#compare is the ONE live cross-tenant read path: it
# `skip_authorization_check`s, loops `Organization.without_demo`, switches the Apartment schema per
# org, and re-serializes each org's identity matches through ClientSerializer with a Phase-5.3
# sensitive-field/domain mask (bulk => break_glass: []). The serializer methods are unit-tested
# single-tenant (spec/serializers/client_serializer_sensitive_fields_spec.rb); this locks the
# REQUEST path end-to-end — the auth-skip, the per-tenant VISIBLE-SET RESET, and the masking.
#
# The fragile bit is the per-tenant recompute inside #find_client_in_organization:
#     @visible_custom_field_ids = nil
#     @visible_domain_levels    = nil
# The visible custom_field id Set is built from the CURRENT tenant's custom_fields table. If that
# reset regressed, tenant A's Set would be reused for tenant B, and an id COLLISION would expose a
# tenant-B restricted field masked-as-standard. The collision example proves the reset is live.
#
# Setup mirrors organization_spec / tenant_boundary_spec: every example runs in the 'app' tenant
# (full_name 'Organization Testing', built in spec_helper's before(:suite)); a second tenant is
# built in-transaction via Organization.create_and_build_tanent and rolled back with the example.
# ClientHistory (Mongo, non-transactional) is cleaned per example — creating a Client custom form
# writes a history row.
RSpec.describe 'api/clients#compare cross-tenant read (POAM-AC3-COMPARE)', type: :request do
  include Devise::Test::IntegrationHelpers

  APP_ORG_NAME = 'Organization Testing' # spec_helper before(:suite): short_name 'app'
  B_ORG_NAME   = 'Tenant B Org'
  LEVELS       = %w[standard restricted emergency_only].freeze

  after(:each) { ClientHistory.delete_all rescue nil }

  # Distinctive per-(tenant,level) value written into a custom-form property. Underscored ->
  # cannot collide with FFaker-generated field data elsewhere in the payload.
  def sentinel(prefix, level)
    "SENTINEL_#{prefix}_#{level}".upcase
  end

  # Attach a standard + restricted + emergency_only Client custom form (each filled with a masked
  # sentinel value) to `client` IN THE CURRENT TENANT.
  def seed_forms_for(client, prefix)
    LEVELS.each do |level|
      cf = create(:custom_field, entity_type: 'Client', sensitivity: level,
                  form_title: "#{prefix} #{level} form",
                  fields: [{ 'type' => 'text', 'label' => 'Note' }])
      create(:custom_field_property, custom_field: cf, custom_formable: client,
             properties: { 'Note' => sentinel(prefix, level) })
    end
  end

  # Build a real second tenant (schema clone happens inside the example transaction and rolls back
  # with it), run the block IN that tenant, then return to 'app' for the request itself.
  def within_tenant_b
    Organization.create_and_build_tanent(short_name: 'tenant-b', full_name: B_ORG_NAME)
    Apartment::Tenant.switch!('tenant-b')
    yield
  ensure
    Apartment::Tenant.switch!('app')
  end

  def organizations_in(body)
    JSON.parse(body).fetch('clients').map { |c| c['organization'] }
  end

  describe 'a signed-in case_worker' do
    # break_glass: [] in the bulk path => emergency_only is masked; a case_worker still sees
    # standard AND restricted (SensitivityPolicy RESTRICTED_ROLES). Verified in BOTH tenants.
    it 'returns identity matches from every tenant and masks emergency_only values in each payload' do
      worker      = create(:user, :case_worker)
      match_name  = 'CompareMatch'

      seed_forms_for(create(:client, given_name: match_name), 'APP')
      within_tenant_b { seed_forms_for(create(:client, given_name: match_name), 'B') }

      sign_in worker
      get compare_api_clients_path, params: { given_name: match_name }

      expect(response).to have_http_status(:ok)
      # cross-tenant: a match from BOTH tenants is returned (proves the loop serialized each schema)
      expect(organizations_in(response.body)).to include(APP_ORG_NAME, B_ORG_NAME)

      # non-vacuity: standard + restricted values DO render for this role, in each tenant
      expect(response.body).to include(sentinel('APP', 'standard'), sentinel('APP', 'restricted'))
      expect(response.body).to include(sentinel('B', 'standard'), sentinel('B', 'restricted'))

      # the mask: emergency_only is stripped from EVERY tenant's payload (bulk break_glass: [])
      expect(response.body).not_to include(sentinel('APP', 'emergency_only'))
      expect(response.body).not_to include(sentinel('B', 'emergency_only'))
    end
  end

  describe 'per-tenant visible-set reset (the cross-tenant leak vector)' do
    # Force a custom_field_id COLLISION across schemas: tenant-A STANDARD id == tenant-B RESTRICTED
    # id. A strategic_overviewer is standard-only, so tenant-B's restricted form must stay masked.
    # If @visible_custom_field_ids were NOT reset between tenants, tenant-A's Set {collide_id} would
    # be reused for tenant-B, whose restricted form shares that id -> it would leak as standard.
    it 'does not leak a tenant-B restricted field whose id collides with a tenant-A standard field' do
      overviewer = create(:user, :strategic_overviewer)
      match_name = 'CollideMatch'
      collide_id = 918_273

      app_client = create(:client, given_name: match_name)
      app_std    = create(:custom_field, id: collide_id, entity_type: 'Client', sensitivity: 'standard',
                          form_title: 'A collide standard', fields: [{ 'type' => 'text', 'label' => 'Note' }])
      create(:custom_field_property, custom_field: app_std, custom_formable: app_client,
             properties: { 'Note' => 'APP_STANDARD_COLLIDE' })

      within_tenant_b do
        b_client = create(:client, given_name: match_name)
        b_res    = create(:custom_field, id: collide_id, entity_type: 'Client', sensitivity: 'restricted',
                          form_title: 'B collide restricted', fields: [{ 'type' => 'text', 'label' => 'Note' }])
        create(:custom_field_property, custom_field: b_res, custom_formable: b_client,
               properties: { 'Note' => 'B_RESTRICTED_COLLIDE' })
      end

      sign_in overviewer
      get compare_api_clients_path, params: { given_name: match_name }

      expect(response).to have_http_status(:ok)
      # both tenants were serialized, so the tenant-B absence below is a real mask, not a skip
      expect(organizations_in(response.body)).to include(APP_ORG_NAME, B_ORG_NAME)

      # tenant-A standard (id == collide_id) IS visible to the overviewer (non-vacuity)
      expect(response.body).to include('APP_STANDARD_COLLIDE')
      # tenant-B restricted, SAME id, stays masked -> the per-tenant reset ran
      expect(response.body).not_to include('B_RESTRICTED_COLLIDE')
    end
  end

  describe 'a signed-in strategic_overviewer' do
    # strategic_overviewer = standard ONLY (never restricted, never emergency, no break-glass) for
    # BOTH custom-field values and CSI domain scores, across every tenant.
    it 'gets standard-only custom fields and standard-only domain data across every tenant' do
      overviewer = create(:user, :strategic_overviewer)
      match_name = 'OverviewMatch'

      app_client = create(:client, given_name: match_name)
      seed_forms_for(app_client, 'APP')

      # standard-only DOMAIN masking (#assessments): standard identity renders, restricted is hidden
      dg      = create(:domain_group)
      std_dom = create(:domain, domain_group: dg, sensitivity: 'standard',   identity: 'STD_DOMAIN_IDENTITY')
      res_dom = create(:domain, domain_group: dg, sensitivity: 'restricted', identity: 'RESTRICTED_DOMAIN_IDENTITY')
      assessment = create(:assessment, client: app_client)
      create(:assessment_domain, assessment: assessment, domain: std_dom)
      create(:assessment_domain, assessment: assessment, domain: res_dom)

      within_tenant_b { seed_forms_for(create(:client, given_name: match_name), 'B') }

      sign_in overviewer
      get compare_api_clients_path, params: { given_name: match_name }

      expect(response).to have_http_status(:ok)
      expect(organizations_in(response.body)).to include(APP_ORG_NAME, B_ORG_NAME)

      # standard custom-field values render in every tenant (non-vacuity)
      expect(response.body).to include(sentinel('APP', 'standard'), sentinel('B', 'standard'))
      # restricted AND emergency custom-field values masked in every tenant
      expect(response.body).not_to include(sentinel('APP', 'restricted'), sentinel('APP', 'emergency_only'))
      expect(response.body).not_to include(sentinel('B', 'restricted'), sentinel('B', 'emergency_only'))

      # standard-only domain data: the standard domain's identity renders, the restricted one is gone
      expect(response.body).to include('STD_DOMAIN_IDENTITY')
      expect(response.body).not_to include('RESTRICTED_DOMAIN_IDENTITY')
    end
  end

  describe 'an unauthenticated request' do
    it 'is rejected (authenticate_user!) and returns no client identities' do
      match_name = 'UnauthMatch'
      create(:client, given_name: match_name) # a would-be match in the 'app' tenant

      # no sign_in
      get compare_api_clients_path, params: { given_name: match_name }

      expect(response).to have_http_status(:found).or have_http_status(:unauthorized)
      # compare never runs, so nothing is serialized: no identity, no tenant name
      expect(response.body).not_to include(match_name)
      expect(response.body).not_to include(APP_ORG_NAME)
    end
  end
end
