# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — "Show additional forms as collapsible sections": filled custom
# forms render on the client Overview as pre-collapsed ibox sections. Contracts:
#   * each visible filled form renders a collapsed section with the newest 3 entries (cap) and
#     the Add entry / View all entries links
#   * SENSITIVITY: the sections use the RECORD-LESS visible set — an emergency-only form (and
#     its values) never renders inline for a non-privileged viewer; the Forms tab / entries
#     pages remain the audited break-glass surfaces
#   * manage-gated links vanish for read-only roles
RSpec.describe 'Client Overview form sections', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:worker)     { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:client) { create(:client, given_name: 'Ovie', family_name: 'Viewsworth', state: 'accepted', users: [worker]) }

  let!(:standard_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Overview Housing Checklist',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Bedrooms' }])
  end
  let!(:entries) do
    4.times.map do |i|
      create(:custom_field_property, custom_field: standard_cf, custom_formable: client,
             properties: { 'Bedrooms' => "OV_ENTRY_#{i}" }, created_at: (10 - i).days.ago)
    end
  end
  let!(:emergency_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Overview Emergency Contact',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Whereabouts' }])
  end
  let!(:emergency_prop) do
    create(:custom_field_property, custom_field: emergency_cf, custom_formable: client,
           properties: { 'Whereabouts' => 'OVERVIEW_SENTINEL_DO_NOT_LEAK' })
  end

  describe 'case worker' do
    before { sign_in_as(worker) }

    it 'renders the collapsed section with the newest 3 entries, links, and no emergency traces' do
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('Overview Housing Checklist')
      expect(body).to include('overview-form-section')
      expect(body).to include('4 entries')
      # newest 3 render inline; the oldest lives behind View all entries (cap)
      expect(body).to include('OV_ENTRY_3')
      expect(body).to include('OV_ENTRY_2')
      expect(body).to include('OV_ENTRY_1')
      expect(body).not_to include('OV_ENTRY_0')
      expect(CGI.unescapeHTML(body)).to include(client_custom_field_properties_path(client, custom_field_id: standard_cf.id))
      expect(CGI.unescapeHTML(body)).to match(%r{custom_field_properties/new\?[^"]*custom_field_id=#{standard_cf.id}})
      # record-less visible set: no emergency title, no value, ever
      expect(body).not_to include('Overview Emergency Contact')
      expect(body).not_to include('OVERVIEW_SENTINEL_DO_NOT_LEAK')
    end
  end

  describe 'strategic overviewer (read-only)' do
    before { sign_in_as(overviewer) }

    it 'sees the section but no Add entry, and still no emergency traces' do
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('Overview Housing Checklist')
      expect(CGI.unescapeHTML(body)).not_to match(%r{custom_field_properties/new\?})
      expect(body).not_to include('Overview Emergency Contact')
      expect(body).not_to include('OVERVIEW_SENTINEL_DO_NOT_LEAK')
    end
  end
end
