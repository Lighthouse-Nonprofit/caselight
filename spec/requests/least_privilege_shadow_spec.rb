# frozen_string_literal: true
require 'rails_helper'

# Phase 5.5 (AC-6) SHADOW-FIRST request proofs.
#
# IMPORTANT (verified against ProgressNotesController#find_client, which loads
# Client.able.accessible_by(current_ability)): every client reachable on a progress_notes page is
# ALREADY bounded to the role's accessible population (status 'Active EC/FC/KC' OR own caseload),
# which is EXACTLY the population the narrowed ProgressNote rule allows. So the per-client
# progress_notes page produces NO shadow divergence -- the ProgressNote narrowing is defense-in-depth
# (it would only bite a hypothetical un-gated ProgressNote read path). The shadow detector's REAL
# divergence signal is the VERSION path: strategic_overviewer reaches version history broadly today,
# and the narrowed rule removes it. These specs prove BOTH: the version shadow fires, and the
# progress_notes page is unchanged with no false-positive divergence.
RSpec.describe 'Least-privilege shadow', type: :request do
  before(:each) { AccessLog.delete_all }
  after(:each) do
    AccessLog.delete_all
    ClientHistory.delete_all
    Rails.application.config.x.enforce_least_privilege = false
  end

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  # --- VERSION path: where the shadow detector actually diverges ---
  describe 'strategic_overviewer version history' do
    let(:so)     { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
    let(:client) { create(:client, able_state: 'Accepted') }

    it 'flag OFF: serves clients#version (200) AND logs ONE strategic_overviewer_version shadow event (counts only)' do
      Rails.application.config.x.enforce_least_privilege = false
      sign_in_as(so)

      expect {
        get client_version_path(client)
      }.to change { AccessLog.where(event_type: 'least_privilege_shadow').count }.by(1)

      expect(response).to have_http_status(:ok)
      ev = AccessLog.where(event_type: 'least_privilege_shadow').last
      expect(ev.metadata['rule']).to eq('strategic_overviewer_version')
      expect(ev.metadata['role']).to eq('strategic overviewer')
      expect(ev.metadata['enforced']).to eq(false)
      expect(ev.metadata['broad_count']).to be_a(Integer)
      expect(ev.metadata['would_deny']).to eq(true)
    end

    it 'flag ON: clients#version is DENIED (no version history) and writes no shadow event' do
      Rails.application.config.x.enforce_least_privilege = true
      sign_in_as(so)

      get client_version_path(client)
      expect(response).not_to have_http_status(:ok) # CanCan::AccessDenied -> redirect
      expect(AccessLog.where(event_type: 'least_privilege_shadow').count).to eq(0)
    end
  end

  # --- ProgressNote path: defense-in-depth, no divergence on the find_client-gated page ---
  describe 'ec_manager progress notes (find_client already bounds the population)' do
    let(:ecm) { create(:user, :ec_manager, password: password, password_confirmation: password) }

    it 'flag OFF: an own-caseload client note index serves 200 with NO shadow divergence' do
      Rails.application.config.x.enforce_least_privilege = false
      own = create(:client, status: 'Active EC', able_state: 'Accepted'); own.users << ecm
      create(:progress_note, client: own)
      sign_in_as(ecm)

      expect {
        get client_progress_notes_path(own)
      }.not_to change { AccessLog.where(event_type: 'least_privilege_shadow').count }
      expect(response).to have_http_status(:ok)
    end

    it 'flag ON: own-caseload AND Active-EC-status clients both serve 200 (the union does not over-restrict)' do
      Rails.application.config.x.enforce_least_privilege = true
      own = create(:client, status: 'Active EC', able_state: 'Accepted'); own.users << ecm
      create(:progress_note, client: own)
      status_client = create(:client, status: 'Active EC', able_state: 'Accepted')
      create(:progress_note, client: status_client)
      sign_in_as(ecm)

      get client_progress_notes_path(own)
      expect(response).to have_http_status(:ok)
      get client_progress_notes_path(status_client)
      expect(response).to have_http_status(:ok)
    end
  end
end
