# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — "Links between individuals, donors, agencies, referral
# sources". Contracts:
#   * client show: Donor + Referral Source rows are NEW (they were invisible outside the edit
#     form); agency/donor/referral-source values link to their index pages ONLY when the
#     viewer can read them (these reference records have no show routes)
#   * agencies + referral_sources indexes gain a linked-individuals column mirroring donors —
#     accessible_by-SCOPED, because every role can reach those pages (leak guard: a case
#     worker never sees a foreign client's name there)
RSpec.describe 'Cross-record links (donor / agency / referral source)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)  { create(:user, :admin, password: password, password_confirmation: password) }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  let!(:agency)          { create(:agency, name: 'CrossSpec Agency') }
  let!(:donor)           { create(:donor, name: 'CrossSpec Donor') }
  let!(:referral_source) { create(:referral_source, name: 'CrossSpec Referrer') }

  let!(:client) do
    create(:client, given_name: 'Linky', family_name: 'Crossworth', state: 'accepted',
                    donor: donor, referral_source: referral_source, agencies: [agency],
                    users: [worker])
  end
  let!(:foreign_client) do
    create(:client, given_name: 'Foreignia', family_name: 'Elsewhere', state: 'accepted',
                    agencies: [agency])
  end

  describe 'client show' do
    it 'admin sees Donor + Referral Source rows with index links, and linked agencies' do
      sign_in_as(admin)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)

      expect(body).to include('CrossSpec Donor')
      expect(body).to include('CrossSpec Referrer')
      expect(body).to match(%r{<a href="#{Regexp.escape(donors_path)}[^"]*">CrossSpec Donor</a>})
      expect(body).to match(%r{<a href="#{Regexp.escape(referral_sources_path)}[^"]*">CrossSpec Referrer</a>})
      expect(body).to match(%r{<a href="#{Regexp.escape(agencies_path)}[^"]*">CrossSpec Agency</a>})
    end

    it 'case worker sees the donor as plain text (no Donor read) but agencies stay linked' do
      sign_in_as(worker)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = CGI.unescapeHTML(response.body)

      expect(body).to include('CrossSpec Donor')
      expect(body).not_to match(%r{<a href="#{Regexp.escape(donors_path)}})
      expect(body).to match(%r{<a href="#{Regexp.escape(agencies_path)}[^"]*">CrossSpec Agency</a>})
    end
  end

  describe 'agencies index (reachable by every role)' do
    it 'links the caseload individual for a case worker and never shows a foreign name' do
      sign_in_as(worker)
      get agencies_path
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('Linky Crossworth')
      expect(CGI.unescapeHTML(body)).to include(client_path(client))
      expect(body).not_to include('Foreignia')
    end

    it 'shows every linked individual to admin' do
      sign_in_as(admin)
      get agencies_path
      expect(response.body).to include('Linky Crossworth')
      expect(response.body).to include('Foreignia Elsewhere')
    end
  end

  describe 'referral sources index' do
    it 'renders the linked-individuals column for admin' do
      sign_in_as(admin)
      get referral_sources_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('CrossSpec Referrer')
      expect(response.body).to include('Linky Crossworth')
      expect(CGI.unescapeHTML(response.body)).to include(client_path(client))
    end
  end
end
