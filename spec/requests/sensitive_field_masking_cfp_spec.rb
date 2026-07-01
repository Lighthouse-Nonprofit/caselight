# frozen_string_literal: true
require 'rails_helper'

# Phase 5.3 masking guard (frontend Unit 6) — custom_field_properties#index, the per-record VALUE
# surface. NON-VACUOUS by construction: a STANDARD form's value DOES render (so "absent" can't be a
# false pass), while a RESTRICTED form's value is only reachable by a permitted role. If a future view
# edit un-masks the restricted value, the overviewer example fails; if it over-masks the standard
# value, the standard example fails.
RSpec.describe 'Sensitive-field masking: custom_field_properties#index', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:client)   { create(:client) }

  let!(:standard_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Unit6 Standard Intake',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Std Note' }])
  end
  let!(:restricted_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Unit6 Restricted Health',
           sensitivity: 'restricted', fields: [{ 'type' => 'text', 'label' => 'Health Note' }])
  end
  let!(:std_prop) do
    create(:custom_field_property, custom_field: standard_cf, custom_formable: client,
           properties: { 'Std Note' => 'STD_SENTINEL_VALUE' })
  end
  let!(:res_prop) do
    create(:custom_field_property, custom_field: restricted_cf, custom_formable: client,
           properties: { 'Health Note' => 'RESTRICTED_SENTINEL_VALUE' })
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def cfp_path(cf)
    client_custom_field_properties_path(client, custom_field_id: cf.id)
  end

  describe 'strategic_overviewer (standard-only)' do
    let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
    before { sign_in_as(overviewer) }

    it 'SEES the standard form value (non-vacuity: values do render for this role)' do
      get cfp_path(standard_cf)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('STD_SENTINEL_VALUE')
    end

    it 'is DENIED the restricted form and its value never reaches the body' do
      get cfp_path(restricted_cf)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('RESTRICTED_SENTINEL_VALUE')
    end
  end

  describe 'case_worker on the caseload (standard + restricted)' do
    let(:worker) { create(:user, :case_worker, password: password, password_confirmation: password) }
    before { client.users << worker; sign_in_as(worker) }

    it 'SEES both the standard and the restricted form values' do
      get cfp_path(standard_cf)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('STD_SENTINEL_VALUE')

      get cfp_path(restricted_cf)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('RESTRICTED_SENTINEL_VALUE')
    end
  end
end
