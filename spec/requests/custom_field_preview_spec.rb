# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D5 — the REAL form preview + duplicate:
#   * preview_draft renders the ACTUAL shared/fields data-entry partials from draft JSON
#   * labels escape exactly as production render does (XSS sentinel)
#   * draft types outside the server allowlist 422 before any partial path interpolates
#   * the preview PAGE (custom_fields#show via /custom_fields/preview) renders real
#     inputs, not the old disabled builder stage
#   * same-org Duplicate pre-fills a "(copy)" form
RSpec.describe 'Custom field preview + duplicate (D5)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin) { create(:user, :admin) }
  before { sign_in admin }

  let(:draft) do
    [
      { 'type' => 'text', 'label' => 'Case number', 'className' => 'form-control' },
      { 'type' => 'select', 'label' => 'Housing status', 'className' => 'form-control',
        'values' => [{ 'label' => 'Stable', 'value' => 'Stable' }] }
    ]
  end

  it 'requires authentication' do
    sign_out admin
    post preview_draft_custom_fields_path, params: { fields: draft.to_json }
    expect(response).to have_http_status(:found)
  end

  it 'renders the real data-entry partials from a draft' do
    post preview_draft_custom_fields_path, params: { fields: draft.to_json }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Case number')
    expect(response.body).to include('Housing status')
    expect(response.body).to match(/<select/)
    expect(response.body).to match(/<input[^>]*Case number/) # properties[Case number] input name
  end

  it 'escapes labels exactly as the production render does' do
    xss = [{ 'type' => 'text', 'label' => '<script>alert(1)</script>', 'className' => 'x' }]
    post preview_draft_custom_fields_path, params: { fields: xss.to_json }
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('<script>alert(1)</script>')
    expect(response.body).to include('&lt;script&gt;')
  end

  it '422s a draft whose type is off the allowlist (never reaches the partial path)' do
    evil = [{ 'type' => '../../layouts/application', 'label' => 'Sneaky' }]
    post preview_draft_custom_fields_path, params: { fields: evil.to_json }
    expect(response).to have_http_status(:unprocessable_entity)
    expect(response.body).to be_blank
  end

  it '422s non-JSON and non-array payloads' do
    post preview_draft_custom_fields_path, params: { fields: 'not json' }
    expect(response).to have_http_status(:unprocessable_entity)
    post preview_draft_custom_fields_path, params: { fields: { a: 1 }.to_json }
    expect(response).to have_http_status(:unprocessable_entity)
  end

  it 'renders the preview PAGE with real inputs instead of the disabled builder stage' do
    cf = CustomField.create!(entity_type: 'Client', form_title: 'Intake Extras', fields: draft)
    get custom_field_path(cf) # #show — same template the /custom_fields/preview collection route renders
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Case number')
    expect(response.body).not_to include('build-wrap') # the builder stage is gone from show
    expect(response.body).to match(/<select/)
  end

  it 'pre-fills a same-org duplicate with a "(copy)" title' do
    cf = CustomField.create!(entity_type: 'Client', form_title: 'Intake Extras', fields: draft)
    get new_custom_field_path(duplicate_from: cf.id)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Intake Extras (copy)')
  end
end
