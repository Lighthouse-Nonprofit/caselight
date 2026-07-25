# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B3) — household alerts: the Alerts tab, the family-overview banner, and the
# member-header chip ("read first" follows the people). Resolve-not-delete. Contracts:
#   * manager raises/edits/resolves; no destroy route exists
#   * the banner renders on families#show and the red chip on a member's client header
#     while an alert is active — and both disappear once resolved
#   * strategic_overviewer mirrors the notes treatment: no access, no tab, no banner
RSpec.describe 'Family alerts', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:manager)    { create(:user, roles: 'manager', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:family) { create(:family, name: 'Alerts Household') }
  let!(:alert)  { create(:family_alert, family: family, severity: 'critical', title: 'ALERT_SPEC_TITLE read first') }

  describe 'manager' do
    before { sign_in_as(manager) }

    it 'lists active alerts on the Alerts tab' do
      get family_family_alerts_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('ALERT_SPEC_TITLE')
      expect(body).to include('alert-danger') # critical severity styling
      expect(CGI.unescapeHTML(body)).to include(resolve_family_family_alert_path(family, alert))
    end

    it 'shows the banner on the family overview and the chip on a member header' do
      client = create(:client, state: 'accepted', users: [manager])
      create(:case, case_type: 'FC', client: client, family: family)

      get family_path(family)
      expect(response.body).to include('family-alert--banner')
      expect(response.body).to include('ALERT_SPEC_TITLE')

      get client_path(client)
      expect(response.body).to include('client-hub__household-alert')
      expect(CGI.unescapeHTML(response.body)).to include(family_family_alerts_path(family))
    end

    it 'raises a new alert stamped with created_by' do
      expect do
        post family_family_alerts_path(family), params: {
          family_alert: { severity: 'notice', title: 'New concern', body: 'Details here' }
        }
      end.to change { family.family_alerts.count }.by(1)
      expect(family.family_alerts.most_recents.first.created_by).to eq(manager)
    end

    it 'resolves an alert (stamps resolver; banner and chip disappear)' do
      client = create(:client, state: 'accepted', users: [manager])
      create(:case, case_type: 'FC', client: client, family: family)

      patch resolve_family_family_alert_path(family, alert)
      expect(alert.reload).not_to be_active
      expect(alert.resolved_by).to eq(manager)

      get family_path(family)
      expect(response.body).not_to include('family-alert--banner')
      get client_path(client)
      expect(response.body).not_to include('client-hub__household-alert')
    end

    it 'has no destroy route (resolve-not-delete)' do
      delete "/families/#{family.id}/family_alerts/#{alert.id}"
      expect(response).to have_http_status(:not_found)
      expect(alert.reload).to be_persisted
    end
  end

  describe 'strategic overviewer' do
    before { sign_in_as(overviewer) }

    it 'is denied the Alerts index and sees neither tab nor banner' do
      get family_family_alerts_path(family)
      expect(response).not_to have_http_status(:ok)

      get family_path(family)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('family-alert--banner')
      expect(response.body).not_to include('ALERT_SPEC_TITLE')
      expect(CGI.unescapeHTML(response.body)).not_to include(family_family_alerts_path(family))
    end
  end
end
