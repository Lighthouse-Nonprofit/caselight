# frozen_string_literal: true
require 'rails_helper'

# POAM-013 (DOMAIN axis) — assessments#download_attachment enforces the Phase-5.3 Domain-sensitivity
# download gate. It serves an assessment_domain attachment's bytes ONLY when the viewer's
# SensitivityPolicy#visible_domain_levels includes the domain's sensitivity
# (levels.include?(assessment_domain.domain.sensitivity)). On denial it renders the STATIC errors/403
# (status :forbidden, NOT a redirect) and writes a 'sensitive_field_denied' AccessLog with metadata
# surface 'assessment_domain_attachment'.
#
# This is the untested MIRROR of the well-covered custom-field axis (authorized_downloads_spec):
#   * Record-level :read is aliased to :download_attachment in Ability, so record-auth holds for a
#     case_worker on their caseload and for a strategic_overviewer (sees all clients). This spec
#     layers the DOMAIN (field) check on top and asserts it FAILS CLOSED.
#   * SensitivityPolicy#visible_domain_levels is unit-tested, but the controller 403/404/log it feeds
#     had no request test until now.
RSpec.describe 'Assessment domain-sensitivity attachment download gate (POAM-013)', type: :request do
  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
  end

  let(:password) { 'SecurePass123!' }

  # 55-byte real PDF. NOT spec/supports/file.docx (zero bytes), which would make every byte assertion
  # vacuous — an empty 403/404 body would "equal" an empty file.
  FIXTURE = 'spec/supports/download_fixture.pdf'

  def uploaded_fixture
    Rack::Test::UploadedFile.new(Rails.root.join(FIXTURE).to_s, 'application/pdf')
  end

  def fixture_bytes
    File.binread(Rails.root.join(FIXTURE))
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:client)     { create(:client, state: 'accepted') }
  let(:assessment) { create(:assessment, client: client) }

  # An assessment_domain on `assessment` whose Domain has `sensitivity`, carrying one downloadable
  # attachment (the fixture) at index 0.
  def ad_with(sensitivity)
    domain = create(:domain, sensitivity: sensitivity)
    create(:assessment_domain, assessment: assessment, domain: domain, attachments: [uploaded_fixture])
  end

  def download_path(ad, index)
    download_attachment_client_assessment_path(client, assessment, assessment_domain_id: ad.id, index: index)
  end

  it 'denies a case_worker an emergency_only-domain attachment with a static 403 (not a redirect) and logs it' do
    worker = create(:user, :case_worker, password: password, password_confirmation: password)
    client.users << worker                      # caseload => record-level :read holds; only the DOMAIN gate can deny
    ad = ad_with('emergency_only')              # emergency_only is masked for EVERY non-admin (no domain break-glass)
    sign_in_as(worker)

    get download_path(ad, 0)

    expect(response).to have_http_status(:forbidden)   # STATIC 403 template...
    expect(response).not_to have_http_status(:redirect) # ...NOT a 302 back to the client
    expect(response.body).not_to eq(fixture_bytes)      # bytes are never served

    log = AccessLog.unscoped.where(event_type: 'sensitive_field_denied').last
    expect(log).to be_present
    expect(log.metadata['surface']).to eq('assessment_domain_attachment')
    expect(log.metadata['domain_id']).to eq(ad.domain_id)
  end

  it 'denies a strategic_overviewer a restricted-domain attachment (standard-only viewer)' do
    overviewer = create(:user, :strategic_overviewer, password: password, password_confirmation: password)
    ad = ad_with('restricted')                 # overviewer's visible_domain_levels == [standard]
    sign_in_as(overviewer)                      # overviewer reads any client, so record-auth holds

    get download_path(ad, 0)

    expect(response).to have_http_status(:forbidden)
    expect(response).not_to have_http_status(:redirect)
    expect(response.body).not_to eq(fixture_bytes)
  end

  it 'serves a standard-domain attachment to a case_worker with attachment disposition (non-vacuous)' do
    worker = create(:user, :case_worker, password: password, password_confirmation: password)
    client.users << worker
    ad = ad_with('standard')                   # standard is visible to restricted-set roles
    sign_in_as(worker)

    get download_path(ad, 0)

    expect(response).to have_http_status(:ok)
    expect(response.headers['Content-Disposition']).to include('attachment')
    expect(response.body).to eq(fixture_bytes) # the exact bytes, proving the allow-path really serves
  end

  it 'returns 404 (not 403, no byte leak) for an out-of-range attachment index on an otherwise-visible domain' do
    worker = create(:user, :case_worker, password: password, password_confirmation: password)
    client.users << worker
    ad = ad_with('standard')                   # gate passes; only index 0 exists
    sign_in_as(worker)

    get download_path(ad, 9)

    expect(response).to have_http_status(:not_found) # missing attachment => 404...
    expect(response).not_to have_http_status(:forbidden)
    expect(response.body).not_to eq(fixture_bytes)   # ...never a byte leak
  end

  it 'fails closed to a 403 when the assessment_domain has no domain association' do
    worker = create(:user, :case_worker, password: password, password_confirmation: password)
    client.users << worker
    ad = ad_with('standard')                   # worker would normally be allowed to see a standard domain...
    ad.update_column(:domain_id, nil)          # ...but an orphaned assessment_domain has no sensitivity to check
    sign_in_as(worker)

    get download_path(ad, 0)

    expect(response).to have_http_status(:forbidden) # `assessment_domain.domain && ...` short-circuits => 403
    expect(response.body).not_to eq(fixture_bytes)

    log = AccessLog.unscoped.where(event_type: 'sensitive_field_denied').last
    expect(log).to be_present
    expect(log.metadata['surface']).to eq('assessment_domain_attachment')
  end
end
