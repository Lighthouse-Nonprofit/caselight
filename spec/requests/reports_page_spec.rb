# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — the Reports landing page (/reports):
# - hosts the CSI-domain + case-statistics charts that used to hide behind an admin-only
#   toggle on clients#index (same div-id + data-attribute contract, CIF.ReportsIndex draws)
# - links the data tools (advanced search + Excel export)
# - authz: authorize_resource class: false — since the reports batch EVERY role opens
#   the page (owner's three-tier decision); the library shows only the viewer's tiers
#   and the show action re-enforces tiers server-side (reports_show_spec)
# - clients#index no longer renders the chart block; its header "Reports" entry is a plain
#   link, shown only to roles that can open the page
RSpec.describe 'Reports landing page', type: :request do
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  context 'as admin' do
    let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }
    before { sign_in_as(admin) }

    it 'renders both charts with their data contracts + the data-tool links' do
      get reports_path
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('cis-domain-score')
      expect(body).to include('data-csi-domain')
      # R8: the flavor-correct enrollments chart replaced the EC/FC/KC case chart
      expect(body).to include('enrollment-statistic')
      expect(body).to include('data-enrollment-statistic')
      expect(body).not_to include('data-case-statistic')
      expect(body).to include(client_advanced_searches_path)
    end

    it 'clients#index dropped the chart block and links here from the header + sidebar' do
      get clients_path
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('client-statistic-body')
      expect(response.body).not_to include('data-csi-domain')
      expect(response.body).to include(reports_path)
    end
  end

  context 'as strategic overviewer' do
    let(:overviewer) { create(:user, roles: 'strategic overviewer', password: password, password_confirmation: password) }
    before { sign_in_as(overviewer) }

    it 'can open the page (read :all)' do
      get reports_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('data-csi-domain')
    end
  end

  context 'as case worker' do
    let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
    before { sign_in_as(worker) }

    it 'opens the page with the worker tier only — no manager/leadership groups' do
      get reports_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('reports.index.tier_worker'))
      expect(response.body).to include('my-caseload-progress')
      expect(response.body).not_to include(I18n.t('reports.index.tier_leadership'))
      expect(response.body).not_to include('served-summary')
    end
  end
end
