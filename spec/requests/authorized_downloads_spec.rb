# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U7) — POAM-SC28-UPLOADS close. Five PII-bearing CarrierWave mounts were raw byte-served
# from public/uploads at guessable URLs with no authorization. Contract:
#   * DownloadsController serves bytes ONLY to a viewer who can :read the parent record, with the
#     Phase-5.3 custom-field sensitivity gate on top for custom-form attachments.
#   * UploadsStaticGuard denies ALL raw /uploads/** except the public org logo.
#
# Behaviour reminders that drive the ROLE choices below (verified against app/classes/ability.rb with
# the least-privilege enforcement flag OFF — the default in this suite):
#   * ProgressNote / ClientEnrollment are readable by EVERY staff role, so the only realistic deny for
#     those two mounts is the documented nil-parent fallback (authorize! :read on the model CLASS,
#     which no ordinary role's rules grant).
#   * CaseNote is readable by every role EXCEPT strategic_overviewer (`cannot :manage, CaseNote` strips
#     the `can :read, :all` grant) — so it is the role used to prove the case-note deny direction.
#   * AbleScreeningQuestion is NOT readable by ec_manager — used to prove the image-mount authz-before-serve.
#   * Client read IS caseload-scoped for a case worker — the cross-caseload deny direction.
#   * The Phase-5.3 gate denies emergency_only custom fields to a case worker (standard+restricted only)
#     but never to admin (sees CustomField.all).
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
  FIXTURE       = 'spec/supports/download_fixture.pdf'
  # A real 200x150 PNG (mini_magick resize_to_fill 100x100 on it produces genuinely different bytes,
  # so the ?version=thumb test can prove the served thumbnail was generated, not the original).
  IMAGE_FIXTURE = 'spec/supports/download_image.png'

  def uploaded_fixture
    Rack::Test::UploadedFile.new(Rails.root.join(FIXTURE).to_s, 'application/pdf')
  end

  def fixture_bytes
    File.binread(Rails.root.join(FIXTURE))
  end

  def uploaded_image
    Rack::Test::UploadedFile.new(Rails.root.join(IMAGE_FIXTURE).to_s, 'image/png')
  end

  def image_bytes
    File.binread(Rails.root.join(IMAGE_FIXTURE))
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

  describe 'form_builder_attachment files (polymorphic — enrollment buildable)' do
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

  # ---------------------------------------------------------------------------------------------------
  # The inline image-serving path + the static version whitelist (?version=thumb). This is the only
  # inline-disposition surface, it ties into the mini_magick 5 upgrade (it serves the generated thumb),
  # and the version param is guarded by a STATIC lookup — params never reach version dispatch.
  # ---------------------------------------------------------------------------------------------------
  describe 'Attachment image mount + ?version=thumb (the inline serve path)' do
    let!(:client)    { create(:client) }
    let!(:note)      { create(:progress_note, client: client) }
    let!(:image_att) { Attachment.create!(progress_note: note, image: uploaded_image) }
    let(:file_att)   { Attachment.create!(progress_note: note, file: uploaded_fixture) }

    it 'serves the image mount inline to an authorized viewer' do
      sign_in_as(admin)
      get authorized_download_path('attachment', image_att.id, 'image')
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('inline')
      expect(response.body).to eq(image_bytes)
    end

    it '?version=thumb serves the generated 100x100 thumbnail inline (bytes differ from the original)' do
      sign_in_as(admin)
      get authorized_download_path('attachment', image_att.id, 'image'), params: { version: 'thumb' }
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('inline')
      # Not the original -> the thumb was actually generated, not passed through.
      expect(response.body).not_to eq(image_bytes)
      # It IS the stored thumb version file (proves the whitelisted version was dispatched).
      expect(response.body).to eq(File.binread(image_att.image.thumb.path))
    end

    it '?version=thumb on the file (non-inline) mount 404s and never serves the bytes' do
      sign_in_as(admin)
      get authorized_download_path('attachment', file_att.id, 'file'), params: { version: 'thumb' }
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to eq(fixture_bytes)
    end

    it '?version=bogus 404s (only the static :thumb value is honoured)' do
      sign_in_as(admin)
      get authorized_download_path('attachment', image_att.id, 'image'), params: { version: 'bogus' }
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to eq(image_bytes)
    end

    it 'denies the image download to a role that cannot read the parent (authz runs before serve)' do
      asq = create(:able_screening_question)
      # progress_note nil -> authz delegates to the able_screening_question, which ec_manager cannot read.
      screening_image = Attachment.create!(able_screening_question: asq, image: uploaded_image)
      ec = create(:user, roles: 'ec manager')
      sign_in_as(ec)
      get authorized_download_path('attachment', screening_image.id, 'image')
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(image_bytes)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # case_note_domain_group — authz delegates to the parent case_note. Serve + deny were both uncovered.
  # ---------------------------------------------------------------------------------------------------
  describe 'case_note_domain_group attachments' do
    let!(:client)    { create(:client) }
    let!(:case_note) { create(:case_note, client: client) }
    let!(:cndg) do
      create(:case_note_domain_group, case_note: case_note, attachments: [uploaded_fixture])
    end

    it 'serves the attachment (attachment disposition) to a viewer who can :read the parent case note' do
      # A case worker holds `can :manage, CaseNote` -> can read every case note.
      worker = create(:user, roles: 'case worker')
      sign_in_as(worker)
      get authorized_download_path('case_note_domain_group', cndg.id, 'attachments', 0)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.body).to eq(fixture_bytes)
    end

    it 'denies a role that cannot :read the parent case note (no bytes served)' do
      # strategic_overviewer is the only role whose `can :read, :all` is stripped for CaseNote.
      overviewer = create(:user, roles: 'strategic overviewer')
      sign_in_as(overviewer)
      get authorized_download_path('case_note_domain_group', cndg.id, 'attachments', 0)
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(fixture_bytes)
    end

    it 'layers the derived domain-GROUP sensitivity gate on top of record-auth (POAM-013)' do
      # Full matrix in case_note_domain_group_attachment_authz_spec — this pins the wiring here:
      # record-auth passes (case worker reads every case note) but the group carries an
      # emergency_only domain, which is masked for every non-admin.
      create(:domain, domain_group: cndg.domain_group, sensitivity: 'emergency_only')
      worker = create(:user, roles: 'case worker')
      sign_in_as(worker)
      get authorized_download_path('case_note_domain_group', cndg.id, 'attachments', 0)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to eq(fixture_bytes)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # form_builder_attachment whose form_buildable IS a CustomFieldProperty — the ONLY place FBA downloads
  # inherit the Phase-5.3 field sensitivity gate (sensitivity_allows? resolves the CFP and applies
  # visible_custom_field_ids_for). The enrollment-backed happy path above never reaches this branch.
  # ---------------------------------------------------------------------------------------------------
  describe 'form_builder_attachment over a CustomFieldProperty (Phase-5.3 sensitivity gate)' do
    let!(:client) { create(:client) }
    let!(:cf) do
      create(:custom_field, entity_type: 'Client', form_title: 'FBA Gate Form',
             fields: [{ 'type' => 'file', 'label' => 'Document', 'name' => 'file-1' }])
    end
    let!(:cfp) { create(:custom_field_property, custom_field: cf, custom_formable: client) }
    let!(:fba) do
      FormBuilderAttachment.create!(form_buildable: cfp, name: 'file-1', file: [uploaded_fixture])
    end

    before { cf.update_columns(sensitivity: 'emergency_only') }

    it 'denies + logs (fail-closed 403) for a case worker who can read the client but not the emergency_only field' do
      worker = create(:user, roles: 'case worker')
      client.users << worker # can read the client + the Client CFP; the FIELD is what is gated
      sign_in_as(worker)
      get authorized_download_path('form_builder_attachment', fba.id, 'file', 0)
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to eq(fixture_bytes)

      log = AccessLog.unscoped.where(event_type: 'sensitive_field_denied').last
      expect(log).to be_present
      expect(log.metadata['record_type']).to eq('form_builder_attachment')
      expect(log.metadata['reason']).to eq('sensitivity')
    end

    it 'serves the same fba to admin (gate passes; proves the polymorphic branch is reachable)' do
      sign_in_as(admin)
      get authorized_download_path('form_builder_attachment', fba.id, 'file', 0)
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.body).to eq(fixture_bytes)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # Parent-delegation authz is the crux of SC28-UPLOADS: a nil parent falls back to authorize! :read on
  # the MODEL CLASS, which no ordinary role's rules grant -> deny. (ProgressNote/ClientEnrollment are
  # universally readable while the enforcement flag is OFF, so this fallback is the realistic deny.)
  # ---------------------------------------------------------------------------------------------------
  describe 'orphaned-parent (nil parent) fallback -> class authorization denies' do
    it 'denies an orphaned attachment (nil progress_note & nil screening question) to a role with no Attachment rule' do
      orphan = Attachment.create!(file: uploaded_fixture) # both parents nil -> authorize! :read, Attachment
      mgr = create(:user, roles: 'manager')               # manager has no `can ..., Attachment` rule
      sign_in_as(mgr)
      get authorized_download_path('attachment', orphan.id, 'file')
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(fixture_bytes)
    end

    it 'denies an orphaned form_builder_attachment (nil form_buildable) to a case worker' do
      orphan = FormBuilderAttachment.create!(form_buildable: nil, name: 'orphan-file', file: [uploaded_fixture])
      worker = create(:user, roles: 'case worker') # no FormBuilderAttachment rule, no `can :read, :all`
      sign_in_as(worker)
      get authorized_download_path('form_builder_attachment', orphan.id, 'file', 0)
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(fixture_bytes)
    end
  end

  # ---------------------------------------------------------------------------------------------------
  # Tenant isolation. The uploaders' store_dir has NO tenant segment (uploads/<model>/<mount>/<id>), so
  # record-scoping via `find` is the ONLY thing keeping one tenant's bytes out of another's response.
  # ---------------------------------------------------------------------------------------------------
  describe 'cross-tenant isolation' do
    after { Apartment::Tenant.drop('tenantb') rescue nil }

    it 'never resolves or serves a record that exists only in another tenant (404, no bytes)' do
      foreign_cfp_id = nil
      Organization.create_and_build_tanent(short_name: 'tenantb', full_name: 'Tenant B')
      Apartment::Tenant.switch('tenantb') do
        other_client = create(:client)
        other_cf = create(:custom_field, entity_type: 'Client', form_title: 'Foreign Form',
                           fields: [{ 'type' => 'file', 'label' => 'Document', 'name' => 'file-1' }])
        other_cfp = create(:custom_field_property, custom_field: other_cf, custom_formable: other_client,
                           attachments: [uploaded_fixture])
        foreign_cfp_id = other_cfp.id
      end

      # Back on the default 'app' tenant (the request host is excluded from the elevator, so the schema
      # stays 'app'): the foreign id resolves to nothing -> themed 404, never the foreign tenant's bytes.
      sign_in_as(admin)
      get authorized_download_path('custom_field_property', foreign_cfp_id, 'attachments', 0)
      expect(response).to have_http_status(:not_found)
      expect(response.body).not_to eq(fixture_bytes)
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

  # POAM-019 (PR B3) — verified-PDF inline viewing. `?disposition=inline` is a serving-mode HINT:
  # honored only for a file with an allowlisted .pdf extension AND %PDF- magic bytes, always with
  # a `Content-Security-Policy: sandbox` response header; everything else silently keeps the
  # Phase-6 attachment discipline. Authorization/sensitivity behave IDENTICALLY on this path.
  describe 'verified-PDF inline viewing (?disposition=inline)' do
    let!(:client) { create(:client) }
    let!(:cf) do
      create(:custom_field, entity_type: 'Client', form_title: 'Inline View Form',
             fields: [{ 'type' => 'file', 'label' => 'Document', 'name' => 'file-1' }])
    end
    let!(:cfp) do
      create(:custom_field_property, custom_field: cf, custom_formable: client,
             attachments: [uploaded_fixture])
    end

    def inline_path(record = cfp, index = 0)
      authorized_download_path('custom_field_property', record.id, 'attachments', index,
                               disposition: 'inline')
    end

    it 'serves a REAL pdf inline, typed application/pdf, with the sandbox CSP' do
      sign_in_as(admin)
      get inline_path
      expect(response).to have_http_status(:ok)
      expect(response.headers['Content-Disposition']).to include('inline')
      expect(response.headers['Content-Type']).to eq('application/pdf')
      expect(response.headers['Content-Security-Policy']).to eq('sandbox')
      expect(response.body).to eq(fixture_bytes)
    end

    it 'without the param the serve is unchanged: attachment, no sandbox header' do
      sign_in_as(admin)
      get authorized_download_path('custom_field_property', cfp.id, 'attachments', 0)
      expect(response.headers['Content-Disposition']).to include('attachment')
      expect(response.headers['Content-Security-Policy']).not_to eq('sandbox')
    end

    it 'a renamed non-PDF (magic-byte mismatch) is NOT served inline — falls back to attachment' do
      fake = Tempfile.new(['not_really', '.pdf'])
      begin
        fake.binmode
        fake.write(image_bytes) # PNG bytes wearing a .pdf name
        fake.flush
        impostor = create(:custom_field_property, custom_field: cf, custom_formable: client,
                          attachments: [Rack::Test::UploadedFile.new(fake.path, 'application/pdf')])

        sign_in_as(admin)
        get inline_path(impostor)
        expect(response).to have_http_status(:ok)
        expect(response.headers['Content-Disposition']).to include('attachment')
        expect(response.headers['Content-Security-Policy']).not_to eq('sandbox')
      ensure
        fake.close!
      end
    end

    it 'the sensitivity gate denies EXACTLY as on the download path (inline is not an access mode)' do
      worker = create(:user, roles: 'case worker')
      client.users << worker
      cf.update_columns(sensitivity: 'emergency_only')

      sign_in_as(worker)
      get inline_path
      expect(response).to have_http_status(:forbidden)
      expect(response.body).not_to eq(fixture_bytes)
    end

    it 'record authorization denies exactly as on the download path' do
      outsider = create(:user, roles: 'case worker')
      sign_in_as(outsider)
      get inline_path
      expect(response).not_to have_http_status(:ok)
      expect(response.body).not_to eq(fixture_bytes)
    end
  end
end
