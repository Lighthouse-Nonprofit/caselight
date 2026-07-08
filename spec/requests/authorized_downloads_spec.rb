# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U7) — POAM-SC28-UPLOADS close. Five PII-bearing CarrierWave mounts were raw byte-served
# from public/uploads at guessable URLs with no authorization. Contract:
#   * DownloadsController serves bytes ONLY to a viewer who can :read the parent record, with the
#     Phase-5.3 custom-field sensitivity gate on top for custom-form attachments.
#   * UploadsStaticGuard denies ALL raw /uploads/** except the public org logo.
RSpec.describe 'Authorized upload downloads', type: :request do
  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
  end

  let(:password) { 'SecurePass123!' }
  let!(:admin)   { create(:user, roles: 'admin') }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  # NOT spec/supports/file.docx — that fixture is ZERO BYTES, which would make every byte
  # assertion here vacuous (an empty 403 body "equals" an empty file).
  FIXTURE = 'spec/supports/download_fixture.pdf'

  def uploaded_fixture
    Rack::Test::UploadedFile.new(Rails.root.join(FIXTURE).to_s, 'application/pdf')
  end

  def fixture_bytes
    File.binread(Rails.root.join(FIXTURE))
  end

  describe 'custom_field_property attachments' do
    let!(:client) { create(:client) }
    let!(:cf) do
      create(:custom_field, entity_type: 'Client', form_title: 'Download Spec Form',
             fields: [{ 'type' => 'file', 'label' => 'Document', 'name' => 'file-1' }])
    end
    let!(:cfp) do
      create(:custom_field_property, custom_field: cf, custom_formable: client,
             attachments: [uploaded_fixture])
    end

    it 'serves the bytes to an authorized viewer with attachment disposition' do
      sign_in_as(admin)
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 0)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.body).to eq(fixture_bytes)
    end

    it 'denies a case worker who cannot read the client (cross-caseload)' do
      outsider = create(:user, roles: 'case worker')
      sign_in_as(outsider)
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 0)
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(fixture_bytes)
    end

    it 'denies via the sensitivity gate even WITH record access, and logs it (fail-closed 403)' do
      worker = create(:user, roles: 'case worker')
      client.users << worker
      cf.update_columns(sensitivity: 'emergency_only')

      sign_in_as(worker)
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 0)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to eq(fixture_bytes)

      log = AccessLog.unscoped.where(event_type: 'sensitive_field_denied').last
      expect(log).to be_present
      expect(log.metadata['surface']).to eq('authorized_download')
    end

    it '404s a bad index without leaking bytes' do
      sign_in_as(admin)
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 9)
      expect(response).to have_http_status(:not_found)
    end

    it 'requires authentication' do
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 0)
      expect(response).to have_http_status(:redirect).or have_http_status(:unauthorized)
      expect(response.body).not_to eq(fixture_bytes)
    end
  end

  describe 'progress-note attachment files' do
    let!(:client) { create(:client, able_state: 'Accepted') }
    let!(:note)   { create(:progress_note, client: client) }
    let!(:att)    { Attachment.create!(progress_note: note, file: uploaded_fixture) }

    it 'serves to an authorized viewer via the parent progress note' do
      sign_in_as(admin)
      get authorized_download_path('attachment', att.id, 'file')
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(fixture_bytes)
    end
  end

  describe 'form_builder_attachment files (polymorphic)' do
    let!(:client)  { create(:client) }
    let!(:program) { create(:program_stream) }
    let!(:enrollment) do
      create(:client_enrollment, client: client, program_stream: program)
    end
    let!(:fba) do
      FormBuilderAttachment.create!(form_buildable: enrollment, name: 'file-1', file: [uploaded_fixture])
    end

    it 'serves to an authorized viewer via the form_buildable parent' do
      sign_in_as(admin)
      get authorized_download_path('form_builder_attachment', fba.id, 'file', 0)
      expect(response).to have_http_status(:ok)
      expect(response.body).to eq(fixture_bytes)
    end
  end

  describe 'UploadsStaticGuard' do
    it 'denies every raw /uploads path except the org logo' do
      sign_in_as(admin)
      %w[
        /uploads/attachment/file/1/x.pdf
        /uploads/attachment/image/1/x.png
        /uploads/custom_field_property/attachments/1/x.pdf
        /uploads/case_note_domain_group/attachments/1/x.pdf
        /uploads/form_builder_attachment/file/1/x.pdf
        /uploads/assessment_domain/attachments/1/x.pdf
      ].each do |path|
        get path
        expect(response).to have_http_status(:forbidden), "expected 403 for #{path}, got #{response.status}"
      end
    end

    it 'lets the org logo path through the guard (404 from static, never 403)' do
      get '/uploads/organization/logo/1/logo.png'
      expect(response).not_to have_http_status(:forbidden)
    end
  end
end
