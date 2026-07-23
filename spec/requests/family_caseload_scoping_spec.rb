# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B4 / R10 — "Case Manager View includes Households") + POAM-022 closure.
# Contracts:
#   * a case worker reads ONLY the households of their own caseload — index list, sidebar
#     link/badge, family hub pages; a foreign household 404s/denies
#   * the caseload rule joins through cases: a household with TWO caseload members must not
#     appear twice (the .distinct guard)
#   * caseload-scoped notes: read + create allowed; alerts: read-only (create denied)
#   * able_manager reaches a household via the able_state union WITHOUT a caseload link
#   * the households index HTML branch is ability-scoped (POAM-022) — foreign households
#     never render for scoped roles
RSpec.describe 'Family caseload scoping', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  let!(:my_family)      { create(:family, name: 'Caseload Household') }
  let!(:foreign_family) { create(:family, name: 'Foreign Household') }

  let!(:my_client_a) { create(:client, state: 'accepted', users: [worker]) }
  let!(:my_client_b) { create(:client, state: 'accepted', users: [worker]) }
  let!(:case_a) { create(:case, case_type: 'FC', client: my_client_a, family: my_family) }
  let!(:case_b) { create(:case, case_type: 'FC', client: my_client_b, family: my_family) }

  let!(:foreign_client) { create(:client, state: 'accepted') }
  let!(:foreign_case)   { create(:case, case_type: 'FC', client: foreign_client, family: foreign_family) }

  describe 'case worker' do
    before { sign_in_as(worker) }

    it 'sees the Households nav link and ONLY caseload households on the index — exactly once' do
      get families_path
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('Caseload Household')
      expect(body).not_to include('Foreign Household')
      # join-duplicate guard: two caseload members in one household -> one card
      expect(body.scan('Caseload Household').size).to eq(1)
    end

    it 'sorts by name and by state without a DISTINCT/ORDER-BY collision (user-reported 500)' do
      # Regression: ability scoping via .distinct broke the grid's expression ORDER BYs under
      # Postgres (LOWER(name) / provinces.name are not in the DISTINCT select list). The
      # id-subquery form must keep both sorts working — and still deduped and scoped.
      get families_path, params: { family_grid: { order: 'name' } }
      expect(response).to have_http_status(:ok)
      expect(response.body.scan('Caseload Household').size).to eq(1)
      expect(response.body).not_to include('Foreign Household')

      get families_path, params: { family_grid: { order: 'province' } }
      expect(response).to have_http_status(:ok)
    end

    it 'opens the caseload family hub but is denied a foreign household' do
      get family_path(my_family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')

      get family_path(foreign_family)
      expect(response).not_to have_http_status(:ok)
    end

    it 'reads and creates caseload household notes' do
      create(:family_note, family: my_family, note: 'WORKER_VISIBLE_NOTE')
      get family_family_notes_path(my_family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('WORKER_VISIBLE_NOTE')

      expect do
        post family_family_notes_path(my_family), params: {
          family_note: { meeting_date: Date.today.to_s, note: 'worker-written note' }
        }
      end.to change { my_family.family_notes.count }.by(1)
    end

    it 'reads caseload alerts but cannot raise one' do
      create(:family_alert, family: my_family, title: 'WORKER_VISIBLE_ALERT')
      get family_family_alerts_path(my_family)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('WORKER_VISIBLE_ALERT')

      expect do
        post family_family_alerts_path(my_family), params: {
          family_alert: { severity: 'caution', title: 'worker-raised' }
        }
      end.not_to change { my_family.family_alerts.count }
    end

    it 'is denied foreign household notes' do
      get family_family_notes_path(foreign_family)
      expect(response).not_to have_http_status(:ok)
    end
  end

  describe 'able manager (able_state union, no caseload link)' do
    let(:able_manager) { create(:user, roles: 'able manager', password: password, password_confirmation: password) }
    let!(:able_client) { create(:client, state: 'accepted', able_state: 'Accepted') }
    let!(:able_family) { create(:family, name: 'Able Household') }
    let!(:able_case)   { create(:case, case_type: 'FC', client: able_client, family: able_family) }

    it 'admin sorts by name without a 500 (unscoped-role regression)' do
      admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
      sign_in_as(admin)
      get families_path, params: { family_grid: { order: 'name' } }
      expect(response).to have_http_status(:ok)
      get families_path(format: :xls), params: { family_grid: { order: 'name' } }
      expect(response).to have_http_status(:ok)
    end

    it 'reaches the able-state household without a caseload link, but not a foreign one' do
      sign_in_as(able_manager)
      get families_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Able Household')
      expect(response.body).not_to include('Foreign Household')

      get family_path(able_family)
      expect(response).to have_http_status(:ok)
    end
  end
end
