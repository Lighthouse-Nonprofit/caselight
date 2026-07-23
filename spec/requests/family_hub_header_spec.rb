# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B1) — the family hub header (families/_family_header.haml): identity strip +
# Actions dropdown + pill tabs (Overview | Forms), rendered on families#show, the family
# Forms page, and family custom_field_properties pages. Contracts:
#   * header + tabs on show (old top form-dropdowns gone; Edit/Delete moved into Actions)
#   * the family Forms page lists filled + available family forms; Phase-5.3 masking holds
#     for family forms (emergency-only titles only in locked rows, only for eligible roles)
#   * family cfp#index renders the family header (was: bare Back button)
#   * strategic_overviewer sees the header but NO Actions dropdown
RSpec.describe 'Family hub header', type: :request do
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)      { create(:user, :admin, password: password, password_confirmation: password) }
  let(:ec_manager) { create(:user, roles: 'ec manager', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:family) { create(:family, name: 'Hub Household') }

  let!(:family_cf) do
    create(:custom_field, entity_type: 'Family', form_title: 'FamilyHub Utilities',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Provider' }])
  end
  let!(:family_prop) do
    # the factory hard-codes custom_formable_type 'Client' — override both together
    create(:custom_field_property, custom_field: family_cf, custom_formable: family,
           custom_formable_type: 'Family', properties: { 'Provider' => 'City Utilities Co' })
  end
  let!(:free_family_cf) do
    create(:custom_field, entity_type: 'Family', form_title: 'FamilyHub Vehicle',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Plate' }])
  end
  let!(:emergency_family_cf) do
    create(:custom_field, entity_type: 'Family', form_title: 'FamilyHub Emergency Wellness',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Concern' }])
  end
  let!(:emergency_family_prop) do
    create(:custom_field_property, custom_field: emergency_family_cf, custom_formable: family,
           custom_formable_type: 'Family', properties: { 'Concern' => 'FAMILY_HUB_SENTINEL' })
  end

  describe 'families#show' do
    it 'renders the header, tabs, and Actions (Edit / Add Form / Delete) for admin' do
      sign_in_as(admin)
      get family_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name')
      expect(body).to include('Hub Household')
      expect(body).to include('client-hub__tabs')
      expect(CGI.unescapeHTML(body)).to include(family_forms_path(family))
      expect(body).to include(edit_family_path(family))
      expect(body).to match(/data-method=["']delete["']/)
      # the old top-of-page form dropdowns are gone
      expect(body).not_to include('Additional Forms')
      # form titles no longer render on show (they live on the Forms tab)
      expect(body).not_to include('FamilyHub Utilities')
    end

    it 'renders the header without an Actions dropdown for a strategic overviewer' do
      sign_in_as(overviewer)
      get family_path(family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')
      expect(response.body).not_to include('client-hub__edit')
    end
  end

  describe 'family Forms page (forms#index)' do
    it 'lists filled + available family forms for admin, with entries links' do
      sign_in_as(admin)
      get family_forms_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name')
      expect(body).to include('FamilyHub Utilities')
      expect(CGI.unescapeHTML(body)).to include(family_custom_field_properties_path(family, custom_field_id: family_cf.id))
      expect(body).to include('FamilyHub Vehicle')
      # admin sees everything -> no locked rows, emergency title renders as a normal row
      expect(body).to include('FamilyHub Emergency Wellness')
      expect(body).not_to include('forms__locked')
      expect(body).not_to include('FAMILY_HUB_SENTINEL')
    end

    it 'renders the emergency-only family form as a locked row + modal for an eligible manager' do
      sign_in_as(ec_manager)
      get family_forms_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('forms__locked')
      expect(body).to include('FamilyHub Emergency Wellness')
      expect(body).to include("break-glass-#{emergency_family_cf.id}")
      expect(body).to match(/name="custom_formable_type"[^>]*value="Family"/)
      expect(CGI.unescapeHTML(body)).not_to include(family_custom_field_properties_path(family, custom_field_id: emergency_family_cf.id))
      expect(body).not_to include('FAMILY_HUB_SENTINEL')
    end

    it 'hides emergency traces and add affordances from a strategic overviewer' do
      sign_in_as(overviewer)
      get family_forms_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('FamilyHub Utilities')
      expect(body).not_to include('forms__locked')
      expect(body).not_to include('FamilyHub Emergency Wellness')
      expect(body).not_to include('FAMILY_HUB_SENTINEL')
      expect(body).not_to include('FamilyHub Vehicle') # available-forms section is manage-gated
    end
  end

  describe 'family custom_field_properties#index' do
    it 'renders the family header with the Forms tab lit (was: bare Back button)' do
      sign_in_as(admin)
      get family_custom_field_properties_path(family, custom_field_id: family_cf.id)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name')
      expect(body).to include('Hub Household')
      expect(body).to match(%r{class="nav-link active" href="[^"]*/forms[^"]*"})
      expect(body).to include('City Utilities Co') # the entry itself renders
    end
  end
end
