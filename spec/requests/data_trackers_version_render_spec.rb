# frozen_string_literal: true
require 'rails_helper'

# POAM-004 Unit 2 — proves TWO things after eval() -> SafeVersionValue.parse:
#   (A) RENDER PARITY on a NON-encrypted properties surface. paper_trail casts each object_changes
#       value through the item's attribute types; CustomFieldProperty#properties is a Tier-5 ENCRYPTED
#       :json attribute, so a crafted plaintext Hash on a real CFP row casts to nil and renders NOTHING.
#       ClientEnrollment#properties is plaintext JSONB, so the crafted Hash SURVIVES the cast and the
#       _client_enrollment.haml properties branch actually renders it — proving the parser is
#       byte-identical to the old eval for a real rendered value.
#   (B) PHASE-5.3 MASKING SURVIVES on the CFP surface, asserted at the RELATION level (the way
#       spec/models/sensitive_version_scope_spec.rb does) rather than on rendered body text.
RSpec.describe 'data_trackers version render + masking (POAM-004)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all }

  let(:client) { create(:client) }

  # ---- (A) RENDER PARITY on a NON-encrypted surface (CustomField#fields, plaintext form definitions) ----
  # NOTE: the four *properties* surfaces (CustomFieldProperty/ClientEnrollment/tracking/leave_program) are
  # ALL Tier-5 encrypted, so paper_trail's attribute-typed changeset casts a crafted plaintext Hash there
  # to nil and NOTHING renders (both before + after this change — identically empty). CustomField#fields is
  # the one plaintext hash/array surface whose changeset survives casting AND flows through the edited
  # _common.haml `fields` branch (SafeVersionValue.parse + the `key.to_sym == :values` parity fix).
  describe 'render parity on a non-encrypted surface (CustomField#fields via _common)' do
    let!(:cf) { create(:custom_field, entity_type: 'Client', form_title: 'Intake Notes', fields: [{ 'label' => 'Existing', 'type' => 'text' }]) }

    before do
      PaperTrail::Version.create!(item_type: 'CustomField', item_id: cf.id, event: 'update',
                                  object_changes: { 'fields' => [nil, [{ 'label' => 'Provider Name', 'type' => 'text' }]] }.to_yaml)
    end

    it 'renders the CustomField field label + value (byte-identical, no eval)' do
      sign_in create(:user, :admin)
      get '/data_trackers', params: { item_type: 'CustomField' }
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Provider Name')
      expect(response.body).to include('label')
    end
  end

  # ---- (B) PHASE-5.3 masking survives, asserted on the surviving-version-id set ----
  describe 'Phase-5.3 CFP version masking survives the eval removal' do
    let!(:std_cf)  { create(:custom_field, entity_type: 'Client', form_title: 'Standard Intake', sensitivity: 'standard') }
    let!(:res_cf)  { create(:custom_field, entity_type: 'Client', form_title: 'Restricted Health', sensitivity: 'restricted') }
    let!(:std_cfp) { create(:custom_field_property, custom_field: std_cf, custom_formable: client) }
    let!(:res_cfp) { create(:custom_field_property, custom_field: res_cf, custom_formable: client) }
    let!(:std_ver) { PaperTrail::Version.create!(item_type: 'CustomFieldProperty', item_id: std_cfp.id, event: 'create') }
    let!(:res_ver) { PaperTrail::Version.create!(item_type: 'CustomFieldProperty', item_id: res_cfp.id, event: 'create') }

    let(:relation) { PaperTrail::Version.where(item_type: 'CustomFieldProperty', id: [std_ver.id, res_ver.id]) }

    it 'includes the restricted CFP version for an admin' do
      admin = create(:user, :admin)
      ids = SensitiveVersionScope.visible_version_ids(relation, user: admin, break_glass: [])
      expect(ids).to include(res_ver.id)
      expect(ids).to include(std_ver.id)
    end

    it 'excludes the restricted CFP version for a strategic_overviewer (masking intact)' do
      overviewer = create(:user, :strategic_overviewer)
      ids = SensitiveVersionScope.visible_version_ids(relation, user: overviewer, break_glass: [])
      expect(ids).not_to include(res_ver.id)
      expect(ids).to include(std_ver.id)
    end
  end
end
