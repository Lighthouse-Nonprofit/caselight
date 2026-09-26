# frozen_string_literal: true
require 'rails_helper'

# Regression (OCA production, 2026-09-22 / 2026-09-24): saving a progress note with an attachment
# fires GET /attachments/delete from progress_notes/form.js, and the action answered with
# `render json: []`. Under the active_model_serializers :json adapter an EMPTY array goes through
# CollectionSerializer, which cannot infer a root key and raised CannotInferRootKeyError -> 500
# (surfacing as a 409 via TenantBoundary). The action now renders a plain Hash, which AMS leaves alone.
RSpec.describe 'GET /attachments/delete', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }
  let(:note)     { create(:progress_note) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'answers 200 with a rooted JSON body when nothing is being deleted (the everyday case)' do
    get '/attachments/delete', params: { progress_note_id: note.id }, xhr: true

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('attachments' => [])
  end

  it 'destroys the named attachments and still answers 200' do
    attachment = create(:attachment, progress_note: note)

    get '/attachments/delete', params: { progress_note_id: note.id, attachments: [attachment.id] }, xhr: true

    expect(response).to have_http_status(:ok)
    expect(JSON.parse(response.body)).to eq('attachments' => [])
    expect(Attachment.exists?(attachment.id)).to be(false)
  end
end
