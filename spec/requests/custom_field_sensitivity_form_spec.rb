# frozen_string_literal: true
require 'rails_helper'

# Phase 5.2b (NIST AC-6) — self-service per-FORM sensitivity designation in the form builder.
# The picker is a top-level simple_form SELECT rendered OUTSIDE the jQuery fields-builder widget
# (sensitivity is a custom_fields column, not a `fields` JSONB entry). These request specs avoid the
# JS builder: `fields` is posted directly as a JSON string (the controller's fields parsing handles
# it), so render + persistence are deterministic. Mirrors spec/requests/login_form_input_types_spec.rb.
# The bare custom_fields path helpers resolve to FormBuilder::CustomFieldsController (config/routes.rb
# `scope '', module: 'form_builder'`); /api/custom_fields is a separate AJAX controller and out of scope.
RSpec.describe 'Form-builder custom field sensitivity designation', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }

  before { sign_in admin }

  # Minimal valid fields payload (the builder normally produces this JSON string).
  let(:fields_json) { [{ 'type' => 'text', 'label' => 'Hello World' }].to_json }

  describe 'new form renders the sensitivity select' do
    it 'renders a <select> for custom_field[sensitivity] with all three levels and no free input' do
      get new_custom_field_path
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to match(/<select[^>]*\bname="custom_field\[sensitivity\]"/),
        'expected a <select> for custom_field[sensitivity] (NOT a free-text input/textarea)'
      expect(body).not_to match(/<(input|textarea)[^>]*\bname="custom_field\[sensitivity\]"/),
        'sensitivity must render as a SELECT, not a free input — check as: :select in _form.haml'

      CustomField::SENSITIVITY_LEVELS.each do |level|
        expect(body).to match(/<option[^>]*\bvalue="#{Regexp.escape(level)}"/),
          "expected an <option value=\"#{level}\"> in the sensitivity select"
      end
    end
  end

  describe 'edit form renders the persisted level as selected' do
    let!(:custom_field) { create(:custom_field, sensitivity: 'restricted') }

    it 'preselects the form current sensitivity' do
      get edit_custom_field_path(custom_field)
      expect(response).to have_http_status(:ok)
      # Rails renders `<option selected="selected" value="restricted">` (selected before value), so match
      # either attribute order.
      expect(response.body).to match(/<option\b[^>]*\bselected[^>]*\bvalue="restricted"|<option\b[^>]*\bvalue="restricted"[^>]*\bselected/),
        'expected the restricted option to be marked selected on edit'
    end
  end

  describe 'create persists the chosen sensitivity' do
    it 'saves restricted when the admin picks it' do
      expect {
        post custom_fields_path, params: { custom_field: {
          entity_type: 'Client', form_title: 'Sensitive Intake', fields: fields_json, sensitivity: 'restricted'
        } }
      }.to change(CustomField, :count).by(1)
      expect(CustomField.last.sensitivity).to eq('restricted')
    end

    it 'saves emergency_only when picked' do
      post custom_fields_path, params: { custom_field: {
        entity_type: 'Client', form_title: 'Break Glass Form', fields: fields_json, sensitivity: 'emergency_only'
      } }
      expect(CustomField.last.sensitivity).to eq('emergency_only')
    end

    it 'defaults to standard when sensitivity is omitted' do
      post custom_fields_path, params: { custom_field: {
        entity_type: 'Client', form_title: 'Plain Form', fields: fields_json
      } }
      expect(CustomField.last.sensitivity).to eq('standard')
    end

    it 'rejects an out-of-band level at the model boundary' do
      expect {
        post custom_fields_path, params: { custom_field: {
          entity_type: 'Client', form_title: 'Bad Form', fields: fields_json, sensitivity: 'top_secret'
        } }
      }.not_to change(CustomField, :count)
    end
  end

  describe 'update changes the sensitivity' do
    let!(:custom_field) { create(:custom_field, sensitivity: 'standard') }

    it 'promotes a standard form to restricted' do
      patch custom_field_path(custom_field), params: { custom_field: {
        entity_type: custom_field.entity_type, form_title: custom_field.form_title,
        fields: custom_field.fields.to_json, sensitivity: 'restricted'
      } }
      # Assert the redirect FIRST: a validation failure (e.g. uniq_fields/field_label on the posted
      # `fields`) would re-render :edit (200) and the reload below would fail for the WRONG reason.
      # A 302 confirms the update saved, so a sensitivity mismatch is a real picker bug.
      expect(response).to have_http_status(:found)
      expect(custom_field.reload.sensitivity).to eq('restricted')
    end
  end
end
