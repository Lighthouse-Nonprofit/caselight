# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (A1) — the Forms partition page (forms#index): the merged, Programs-style forms
# surface that replaced the Overview Forms card. Contracts:
#   * hub header renders with the Forms tab active; filled forms list with entry count +
#     latest-entry date + View-entries link (cfp#index = the dated-entries page)
#   * Phase-5.3 visibility holds: emergency-only form titles never appear for a non-elevated
#     viewer outside the break-glass locked-row affordance (and values never appear at all)
#   * Add entry / Available forms render only for can? :manage, CustomFieldProperty
#   * locked rows + per-form modals render only for break-glass-ELIGIBLE viewers
RSpec.describe 'Client Forms page', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)      { create(:user, :admin, password: password, password_confirmation: password) }
  let(:worker)     { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:client) { create(:client, given_name: 'Paige', family_name: 'Formsworth', state: 'accepted', users: [worker]) }

  let!(:standard_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'FormsPage Intake',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Notes' }])
  end
  let!(:standard_prop_old) do
    create(:custom_field_property, custom_field: standard_cf, custom_formable: client,
           properties: { 'Notes' => 'first entry' }, created_at: 3.days.ago)
  end
  let!(:standard_prop_new) do
    create(:custom_field_property, custom_field: standard_cf, custom_formable: client,
           properties: { 'Notes' => 'second entry' })
  end
  let!(:free_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'FormsPage Unstarted',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Anything' }])
  end
  let!(:emergency_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'FormsPage Emergency Contact',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Whereabouts' }])
  end
  let!(:emergency_prop) do
    create(:custom_field_property, custom_field: emergency_cf, custom_formable: client,
           properties: { 'Whereabouts' => 'FORMS_PAGE_SENTINEL' })
  end

  describe 'admin' do
    before { sign_in_as(admin) }

    it 'renders the hub header, name-linked filled rows, and the Add-new-form picker' do
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      # hub header with the Forms tab lit
      expect(body).to include('client-hub__name')
      expect(body).to include('Paige Formsworth')
      expect(body).to match(%r{class="nav-link active" href="[^"]*/forms[^"]*"})
      # filled form row: the NAME is the entries link (investor UX round — button retired)
      expect(body).to include('FormsPage Intake')
      expect(CGI.unescapeHTML(body)).to include(client_custom_field_properties_path(client, custom_field_id: standard_cf.id))
      expect(body).to match(/<td>\s*2\s*<\/td>/)
      expect(body).not_to include('View entries')
      # admin sees every filled title (no lock affordance — admin sees all, so no candidates)
      expect(body).to include('FormsPage Emergency Contact')
      # the available-forms TABLE is gone; unstarted forms live in the Add-new-form dropdown
      expect(body).not_to include('Available forms')
      expect(body).to include('Add new form')
      expect(body).to include('FormsPage Unstarted')
      expect(CGI.unescapeHTML(body)).to include(new_client_custom_field_property_path(client, custom_field_id: free_cf.id))
    end
  end

  describe 'family hub (the same polymorphic view)' do
    let!(:family)    { create(:family, name: 'Formsworth House') }
    let!(:family_cf) do
      create(:custom_field, entity_type: 'Family', form_title: 'FormsPage Household Check',
             sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Anything' }])
    end

    it 'renders the family header and the Add-new-form picker' do
      sign_in_as(admin)
      get family_forms_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('Formsworth House')
      expect(body).to include('Add new form')
      expect(body).to include('FormsPage Household Check')
      expect(CGI.unescapeHTML(body)).to include(new_family_custom_field_property_path(family, custom_field_id: family_cf.id))
      expect(body).not_to include('Available forms')
    end
  end

  describe 'case worker (break-glass eligible, not elevated)' do
    before { sign_in_as(worker) }

    it 'masks the emergency title outside the locked row and never leaks values' do
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('FormsPage Intake')
      # the emergency form appears ONLY as a locked row (no entries link, no value)
      expect(body).to include('forms__locked')
      expect(body).to include('FormsPage Emergency Contact')
      expect(body).to include("break-glass-#{emergency_cf.id}")
      expect(CGI.unescapeHTML(body)).not_to include(client_custom_field_properties_path(client, custom_field_id: emergency_cf.id))
      expect(body).not_to include('FORMS_PAGE_SENTINEL')
    end
  end

  describe 'strategic overviewer (read-only, never eligible)' do
    before { sign_in_as(overviewer) }

    it 'sees filled standard forms but no add/available affordances and no emergency traces' do
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('FormsPage Intake')
      # no manage rights: no Add entry, no Available forms section
      expect(CGI.unescapeHTML(body)).not_to include(new_client_custom_field_property_path(client, custom_field_id: standard_cf.id))
      expect(body).not_to include('FormsPage Unstarted')
      # never break-glass eligible: no locked rows, no emergency title, no value
      expect(body).not_to include('forms__locked')
      expect(body).not_to include('FormsPage Emergency Contact')
      expect(body).not_to include('FORMS_PAGE_SENTINEL')
    end
  end

  describe 'a client with nothing filled' do
    it 'renders the empty state (the tab exists even at zero forms)' do
      bare_client = create(:client, given_name: 'Blank', family_name: 'Slate', state: 'accepted')
      sign_in_as(admin)
      get client_forms_path(bare_client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('No forms filled yet.')
    end
  end
end
