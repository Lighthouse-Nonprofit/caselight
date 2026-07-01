# frozen_string_literal: true
require 'rails_helper'

# Phase 5.3 masking guard (frontend Unit 6) — clients#show custom-form dropdowns. The form TITLE is
# itself need-to-know metadata (a "Trafficking Safety" / "Immigration" form name reveals a sensitive
# fact before you open it). NON-VACUOUS: in the SAME overviewer response the standard title is PRESENT
# and the restricted title is ABSENT — so it fails on both over-mask (standard gone) and un-mask
# (restricted appears).
RSpec.describe 'Sensitive-field masking: clients#show custom-form dropdowns', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  # state:'accepted' so clients#show renders the detail-actions region (the custom-form dropdowns);
  # a bare client (state == '') only renders the accept/reject screening form.
  let(:client)   { create(:client, state: 'accepted') }

  let!(:standard_cf)   { create(:custom_field, entity_type: 'Client', form_title: 'Unit6 Standard Housing', sensitivity: 'standard') }
  let!(:restricted_cf) { create(:custom_field, entity_type: 'Client', form_title: 'Unit6 Restricted Immigration', sensitivity: 'restricted') }
  # Filled forms (=> the @group_client_custom_fields "additional forms" dropdown lists their titles).
  let!(:std_prop) { create(:custom_field_property, custom_field: standard_cf, custom_formable: client) }
  let!(:res_prop) { create(:custom_field_property, custom_field: restricted_cf, custom_formable: client) }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'strategic_overviewer (standard-only)' do
    let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
    before { sign_in_as(overviewer) }

    it 'lists the standard form title but NOT the restricted one' do
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Unit6 Standard Housing')       # non-vacuity: titles do render
      expect(response.body).not_to include('Unit6 Restricted Immigration')
    end
  end

  describe 'case_worker on the caseload (standard + restricted)' do
    let(:worker) { create(:user, :case_worker, password: password, password_confirmation: password) }
    before { client.users << worker; sign_in_as(worker) }

    it 'lists both the standard and the restricted form titles' do
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Unit6 Standard Housing')
      expect(response.body).to include('Unit6 Restricted Immigration')
    end
  end
end
