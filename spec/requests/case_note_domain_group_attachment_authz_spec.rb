# frozen_string_literal: true
require 'rails_helper'

# POAM-013 (domain-GROUP axis) — downloads#show enforces the derived domain-group sensitivity gate
# for case_note_domain_group attachments. Sensitivity lives on Domain; a case-note section covers
# ALL of its group's domains and the file cannot be attributed to a single domain, so the viewer's
# visible_domain_levels must cover EVERY domain in the group (most-sensitive governs). On denial:
# STATIC errors/403 + values-free sensitive_field_denied AccessLog (surface authorized_download,
# reason sensitivity). Mirrors assessment_domain_attachment_authz_spec (the per-domain axis).
#
# Role reality: every role that can :read CaseNote is either admin (all levels) or restricted-set
# ([standard, restricted]) — strategic_overviewer cannot read case notes at all (record-auth denies
# first; covered in authorized_downloads_spec). So the live protections here are the emergency_only
# level and the mixed-group most-sensitive-governs rule.
RSpec.describe 'Case-note domain-group attachment download gate (POAM-013)', type: :request do
  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
  end

  let(:password) { 'SecurePass123!' }

  # 55-byte real PDF (never spec/supports/file.docx — zero bytes makes byte assertions vacuous).
  def fixture_path
    Rails.root.join('spec/supports/download_fixture.pdf')
  end

  def uploaded_fixture
    Rack::Test::UploadedFile.new(fixture_path.to_s, 'application/pdf')
  end

  def fixture_bytes
    File.binread(fixture_path)
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:client)    { create(:client, state: 'accepted') }
  let(:case_note) { create(:case_note, client: client) }

  # A case-note section whose domain GROUP contains one domain per given sensitivity, carrying the
  # downloadable fixture at index 0.
  def cndg_with(*sensitivities)
    group = create(:domain_group)
    sensitivities.each { |s| create(:domain, domain_group: group, sensitivity: s) }
    create(:case_note_domain_group, case_note: case_note, domain_group: group,
                                    attachments: [uploaded_fixture])
  end

  def download_path(cndg, index)
    authorized_download_path('case_note_domain_group', cndg.id, 'attachments', index)
  end

  def case_worker
    create(:user, :case_worker, password: password, password_confirmation: password)
  end

  it 'denies a case_worker when the group contains an emergency_only domain (static 403 + log)' do
    cndg = cndg_with('emergency_only')   # emergency_only is masked for EVERY non-admin
    sign_in_as(case_worker)              # case workers can :manage CaseNote => record-auth holds

    get download_path(cndg, 0)

    expect(response).to have_http_status(:forbidden)     # STATIC 403 template...
    expect(response).not_to have_http_status(:redirect)  # ...NOT a 302
    expect(response.body).not_to eq(fixture_bytes)       # bytes are never served

    log = AccessLog.unscoped.where(event_type: 'sensitive_field_denied').last
    expect(log).to be_present
    expect(log.metadata['surface']).to eq('authorized_download')
    expect(log.metadata['record_type']).to eq('case_note_domain_group')
    expect(log.metadata['reason']).to eq('sensitivity')
  end

  it 'most-sensitive governs: one emergency_only domain masks the whole group even beside standard ones' do
    cndg = cndg_with('standard', 'emergency_only', 'standard')
    sign_in_as(case_worker)

    get download_path(cndg, 0)

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to eq(fixture_bytes)
  end

  it 'serves an all-standard group to a case_worker with attachment disposition (non-vacuous)' do
    cndg = cndg_with('standard', 'standard')
    sign_in_as(case_worker)

    get download_path(cndg, 0)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('attachment')
    expect(response.body).to eq(fixture_bytes)
  end

  it 'does not over-mask: a restricted-domain group is visible to a restricted-set role' do
    cndg = cndg_with('standard', 'restricted')  # case worker sees [standard, restricted]
    sign_in_as(case_worker)

    get download_path(cndg, 0)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(fixture_bytes)
  end

  it 'serves an emergency_only group to an admin (all levels visible)' do
    cndg  = cndg_with('emergency_only')
    admin = create(:user, :admin, password: password, password_confirmation: password)
    sign_in_as(admin)

    get download_path(cndg, 0)

    expect(response).to have_http_status(:ok)
    expect(response.body).to eq(fixture_bytes)
  end

  it 'returns 404 (not 403, no byte leak) for an out-of-range index on a visible group' do
    cndg = cndg_with('standard')
    sign_in_as(case_worker)

    get download_path(cndg, 9)

    expect(response).to have_http_status(:not_found)
    expect(response.body).not_to eq(fixture_bytes)
  end

  it 'fails closed to a 403 when the section has no domain group' do
    cndg = cndg_with('standard')
    cndg.update_column(:domain_group_id, nil)  # orphaned row bypassing the presence validation
    sign_in_as(case_worker)

    get download_path(cndg, 0)

    expect(response).to have_http_status(:forbidden)
    expect(response.body).not_to eq(fixture_bytes)
  end

  describe 'case-notes index masking (the view-side sibling of the download gate)' do
    it 'masks the attachment card for a non-admin when the group carries an emergency_only domain' do
      cndg   = cndg_with('emergency_only')
      worker = case_worker
      client.users << worker # the index is caseload-scoped (unlike the download route's record-auth)
      sign_in_as(worker)

      get client_case_notes_path(client)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Restricted — not authorized to view')
      expect(response.body).not_to include(download_path(cndg, 0))
    end

    it 'shows the download link to an admin' do
      cndg  = cndg_with('emergency_only')
      admin = create(:user, :admin, password: password, password_confirmation: password)
      sign_in_as(admin)

      get client_case_notes_path(client)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include(download_path(cndg, 0))
      expect(response.body).not_to include('Restricted — not authorized to view')
    end
  end
end
