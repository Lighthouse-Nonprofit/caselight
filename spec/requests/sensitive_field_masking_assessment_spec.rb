# frozen_string_literal: true
require 'rails_helper'

# Phase 5.3 masking guard (frontend Unit 6) — assessments#show domain masking. Assessment scores/notes
# live on the assessment_domains join, gated by domain_visible?(ad.domain) (domains.sensitivity). The
# domain NAME always renders; the SCORE + REASON render only for a permitted viewer. NON-VACUOUS: the
# standard domain's reason IS present in the same overviewer response while the restricted one's is not.
RSpec.describe 'Sensitive-field masking: assessment domain scores/notes', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password)   { 'SecurePass123!' }
  let(:client)     { create(:client, state: 'accepted') }
  let(:assessment) { create(:assessment, client: client) }
  let!(:dg)          { create(:domain_group) }
  let!(:std_domain)  { create(:domain, domain_group: dg, sensitivity: 'standard') }
  let!(:res_domain)  { create(:domain, domain_group: dg, sensitivity: 'restricted') }
  let!(:std_ad) { create(:assessment_domain, assessment: assessment, domain: std_domain, reason: 'STANDARD_DOMAIN_REASON_X') }
  let!(:res_ad) { create(:assessment_domain, assessment: assessment, domain: res_domain, reason: 'RESTRICTED_DOMAIN_REASON_X') }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'strategic_overviewer (standard-only)' do
    let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
    before { sign_in_as(overviewer) }

    it 'shows the standard domain reason but MASKS the restricted domain reason' do
      get client_assessment_path(client, assessment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('STANDARD_DOMAIN_REASON_X')       # non-vacuity: notes do render
      expect(response.body).not_to include('RESTRICTED_DOMAIN_REASON_X')
    end
  end

  describe 'case_worker on the caseload (standard + restricted)' do
    let(:worker) { create(:user, :case_worker, password: password, password_confirmation: password) }
    before { client.users << worker; sign_in_as(worker) }

    it 'shows both domain reasons' do
      get client_assessment_path(client, assessment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('STANDARD_DOMAIN_REASON_X')
      expect(response.body).to include('RESTRICTED_DOMAIN_REASON_X')
    end
  end
end
