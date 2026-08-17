# frozen_string_literal: true
require 'rails_helper'

# Two UX unlocks (2026-08):
#   (1) the flexible Progress Note (voicemails / follow-up texts, etc.) was gated to the ABLE
#       program, invisible in the youth flavor — now available on ANY client, both flavors,
#       alongside domain-based Case Notes.
#   (2) case workers can now CREATE household alerts on their OWN caseload's households
#       (previously read-only).
RSpec.describe 'Notes + Alerts unlock', type: :request do
  include Devise::Test::IntegrationHelpers

  describe 'Progress notes on a non-ABLE client' do
    let!(:admin) { create(:user, roles: 'admin') }
    let(:client) { create(:client).tap { |c| c.update_column(:able_state, nil) } }
    before { sign_in admin }

    it 'opens the progress-notes surface on a non-ABLE client (was a 404)' do
      expect(client.reload.able?).to be(false)
      get client_progress_notes_path(client)
      expect(response).to have_http_status(:ok)
    end

    it 'creates a flexible progress note (e.g. a voicemail) on a non-ABLE client' do
      type = ProgressNoteType.create!(note_type: 'Voicemail')
      expect do
        post client_progress_notes_path(client), params: { progress_note: {
          date: Date.current.to_s, user_id: admin.id, progress_note_type_id: type.id,
          response: 'Left a voicemail (demo).'
        } }
      end.to change { client.progress_notes.count }.by(1)
    end
  end

  describe 'Alerts: a case worker creating one on their own caseload household' do
    let!(:worker) { create(:user, roles: 'case worker') }
    let(:client)  { create(:client) }
    let(:family)  { create(:family) }
    before do
      client.users = [worker]
      Case.create!(family: family, client: client, case_type: 'KC', start_date: Date.current)
      sign_in worker
    end

    it 'grants scoped create on FamilyAlert' do
      expect(Ability.new(worker).can?(:create, FamilyAlert.new(family: family))).to be(true)
    end

    it 'creates the alert via the nested route' do
      expect do
        post family_family_alerts_path(family), params: { family_alert: {
          severity: 'caution', title: 'Heads up', body: 'Read first (demo).'
        } }
      end.to change { FamilyAlert.where(family: family).count }.by(1)
    end
  end
end
