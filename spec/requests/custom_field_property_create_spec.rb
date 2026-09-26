# frozen_string_literal: true
require 'rails_helper'

# Regression (2026-06-26) — adding custom-form data via the web form POSTed the dynamic `properties`
# hash as UNPERMITTED ActionController::Parameters. Phase 4 Tier 5 made CustomFieldProperty#properties
# an encrypted :json attribute whose AR cast calls #to_h on the assigned value, and #to_h on
# unpermitted params raises ActionController::UnfilteredParameters -> a 500 on every custom-form
# create/update (and the same pattern on client_enrollment(_tracking)/leave_program). The fix permits
# the properties sub-hash (a single JSON blob, no model-column mass-assignment surface) in
# FormBuilderAttachments#properties_params.
RSpec.describe 'CustomFieldProperty create via the form (properties params)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:client)   { create(:client) }
  let!(:cf)      { create(:custom_field, entity_type: 'Client', form_title: 'Intake Notes', sensitivity: 'standard') }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'persists the submitted properties (no UnfilteredParameters)' do
    expect {
      post client_custom_field_properties_path(client, custom_field_id: cf.id), params: {
        custom_field_id: cf.id,
        custom_field_property: { properties: { 'Diagnosis' => 'PTSD', 'Notes' => 'stable' } }
      }
    }.to change(CustomFieldProperty, :count).by(1)

    expect(response).to have_http_status(:found) # redirect on success (not a 500)
    cfp = CustomFieldProperty.last
    expect(cfp.properties['Diagnosis']).to eq('PTSD')
    expect(cfp.properties['Notes']).to eq('stable')
  end

  # Regression (OCA production, 2026-09-24, seven retries): a custom-form save WITH a file attached
  # merged the nested form_builder_attachments_attributes hash while it was still UNPERMITTED, so the
  # model cast raised ActionController::UnfilteredParameters -> 500. attachment_params now permits
  # the sub-hash exactly like properties_params.
  it 'persists a file attached to the form (no UnfilteredParameters on the nested attachments)' do
    upload = Rack::Test::UploadedFile.new(Rails.root.join('spec/supports/download_image.png'), 'image/png')

    expect {
      post client_custom_field_properties_path(client, custom_field_id: cf.id), params: {
        custom_field_id: cf.id,
        custom_field_property: {
          properties: { 'Diagnosis' => 'PTSD' },
          form_builder_attachments_attributes: { '0' => { name: 'Photo', file: [upload] } }
        }
      }
    }.to change(CustomFieldProperty, :count).by(1)

    expect(response).to have_http_status(:found)
    attachments = CustomFieldProperty.last.form_builder_attachments
    expect(attachments.pluck(:name)).to eq(['Photo'])
    expect(attachments.first.file.size).to eq(1)
  end

end
