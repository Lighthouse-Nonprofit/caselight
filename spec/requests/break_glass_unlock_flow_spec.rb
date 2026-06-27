# frozen_string_literal: true
require 'rails_helper'

# Phase 5.3 + 5.4 — the break-glass UNLOCK flow on custom_field_properties#index (the per-record
# value surface). Proves: an emergency_only form is masked from an eligible case worker (they get the
# elevation PROMPT, not the values); an ineligible strategic_overviewer gets a static 403 (no
# elevation path — a grant would not widen their view); a 1h grant unlocks exactly that form.
RSpec.describe 'Break-glass unlock flow (cfp#index)', type: :request do
  before(:each) { AccessLog.delete_all }
  after(:each)  { AccessLog.delete_all; ClientHistory.delete_all }

  let(:password)      { 'SecurePass123!' }
  let(:client)        { create(:client) }
  let!(:emergency_cf) { create(:custom_field, entity_type: 'Client', form_title: 'BG Emergency Form', sensitivity: 'emergency_only') }
  let!(:property)     { create(:custom_field_property, custom_field: emergency_cf, custom_formable: client) }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def cfp_index_path
    client_custom_field_properties_path(client, custom_field_id: emergency_cf.id)
  end

  describe 'an eligible case worker on their own caseload' do
    let(:worker) { create(:user, :case_worker, password: password, password_confirmation: password) }
    before { client.users << worker; sign_in_as(worker) }

    it 'shows the break-glass prompt (not the values) for an emergency_only form with no grant' do
      get cfp_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Request emergency access')
      expect(response.body).to include(break_glass_grants_path)
    end

    it 'unlocks the form for 1h after a grant, and no longer shows the prompt' do
      expect {
        post break_glass_grants_path, params: {
          custom_formable_type: 'Client', custom_formable_id: client.id,
          custom_field_id: emergency_cf.id, reason: 'home visit safety concern'
        }
      }.to change {
        BreakGlassGrant.active.where(user_id: worker.id, custom_formable_id: client.id, custom_field_id: emergency_cf.id).count
      }.by(1)

      get cfp_index_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Request emergency access')
    end
  end

  describe 'an ineligible strategic_overviewer' do
    let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
    before { sign_in_as(overviewer) }

    it 'is denied (static 403, no elevation prompt) on an emergency_only form' do
      get cfp_index_path
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to include('Request emergency access')
    end
  end
end
