# frozen_string_literal: true
require 'rails_helper'

# UX rung 4 — the client hub header (clients/_client_header.haml): a persistent identity strip
# + pill tab bar (Overview | Programs | Forms | Case Notes | Assessments | Tasks) rendered on
# clients#show AND every client partition page, replacing the old show-page button strip and
# the partitions' bare Back links. Contracts:
#   * header + tabs on show and each partition, for admin and worker alike
#   * the Forms dropdown lists ONLY the viewer's visible filled forms (Phase-5.3 record-aware
#     set — emergency-only titles never appear for a non-elevated viewer)
#   * tabs render only for accepted clients (pre-existing gating)
#   * the polymorphic custom_field_properties page renders the header ONLY for Client records
RSpec.describe 'Client hub header', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)  { create(:user, :admin, password: password, password_confirmation: password) }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  let!(:client) { create(:client, given_name: 'Hubert', family_name: 'Header', state: 'accepted', users: [worker]) }

  let!(:standard_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'HubSpec Intake',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Notes' }])
  end
  let!(:standard_prop) do
    create(:custom_field_property, custom_field: standard_cf, custom_formable: client,
           properties: { 'Notes' => 'standard notes' })
  end
  let!(:emergency_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'HubSpec Emergency Whereabouts',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Whereabouts' }])
  end
  let!(:emergency_prop) do
    create(:custom_field_property, custom_field: emergency_cf, custom_formable: client,
           properties: { 'Whereabouts' => 'EMERGENCY_HUB_SENTINEL' })
  end

  describe 'clients#show' do
    it 'renders the hub header, tabs, and the Edit dropdown with delete for admin' do
      sign_in_as(admin)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name')
      expect(body).to include('Hubert Header')
      expect(body).to match(/client-hub__tabs/)
      expect(body).to include(client_client_enrollments_path(client))
      expect(body).to include(client_case_notes_path(client))
      expect(body).to include(client_assessments_path(client))
      expect(body).to include(client_tasks_path(client))
      # Edit dropdown carries edit + delete (one canonical spot)
      expect(body).to include(edit_client_path(client))
      expect(body).to match(/data-method=["']delete["']/)
      # admin sees every filled form title in the Forms dropdown
      expect(body).to include('HubSpec Intake')
      expect(body).to include('HubSpec Emergency Whereabouts')
    end

    it 'omits emergency-only form titles from the Forms dropdown for a non-elevated worker' do
      sign_in_as(worker)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__tabs')
      expect(body).to include('HubSpec Intake')
      # the emergency title may legitimately appear via the break-glass affordance (plain
      # links in the show-body Emergency-forms dropdown) — but never as a hub Forms
      # dropdown-item (link_to renders class before href)
      emergency_cfp_path = client_custom_field_properties_path(client, custom_field_id: emergency_cf.id)
      expect(body).not_to match(/class="dropdown-item"[^>]*href="[^"]*#{Regexp.escape(emergency_cfp_path)}/)
      # and the sentinel VALUE never reaches this viewer's page
      expect(body).not_to include('EMERGENCY_HUB_SENTINEL')
    end

    it 'renders the header without tabs for a not-yet-accepted client' do
      pending_client = create(:client, given_name: 'Pending', family_name: 'Person', state: '')
      sign_in_as(admin)
      get client_path(pending_client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
      expect(response.body).not_to include('client-hub__tabs')
    end
  end

  describe 'partition pages' do
    before { sign_in_as(admin) }

    it 'client_enrollments (merged Programs page) carries the header + the enrolled section scaffold' do
      get client_client_enrollments_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
      expect(response.body).to include('client-hub__tabs')
    end

    it 'case_notes carries the header' do
      get client_case_notes_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
    end

    it 'assessments carries the header' do
      get client_assessments_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
    end

    it 'tasks carries the header' do
      get client_tasks_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
    end

    it 'custom_field_properties carries the header for a Client record' do
      get client_custom_field_properties_path(client, custom_field_id: standard_cf.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
    end

    it 'custom_field_properties does NOT render the client header for a Family record' do
      # (no property rows needed — the page renders an empty index; the cfp factory is
      # client-shaped and its create_client_history callback breaks for Family formables)
      family_cf = create(:custom_field, entity_type: 'Family', form_title: 'HubSpec Family Form',
                         fields: [{ 'type' => 'text', 'label' => 'Info' }])
      family    = create(:family)
      get family_custom_field_properties_path(family, custom_field_id: family_cf.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('client-hub__name')
    end
  end
end
