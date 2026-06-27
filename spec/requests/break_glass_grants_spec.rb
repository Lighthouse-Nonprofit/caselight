# frozen_string_literal: true
require 'rails_helper'

# Phase 5.4 — break-glass endpoint (NIST AC-3 / AC-6(2) / AU-2). Drives the DEDICATED controller
# through the real auth + rescue stack. AccessLog (Mongo) is not auto-cleaned -> delete_all around
# each example; auth via the real POST /users/sign_in path (matching security_events_spec).
RSpec.describe 'Break-glass emergency access (AC-3 / AU-2)', type: :request do
  before(:each) { AccessLog.delete_all }
  after(:each)  { AccessLog.delete_all; ClientHistory.delete_all }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'a permitted (own-caseload) user' do
    it 'creates a 1h grant and writes the break_glass audit row FIRST (values-free metadata)' do
      worker = create(:user, :case_worker, password: password, password_confirmation: password)
      client = create(:client)
      client.users << worker
      sign_in_as(worker)

      expect {
        post break_glass_grants_path, params: { custom_formable_type: 'Client', custom_formable_id: client.id, custom_field_id: 99, reason: 'Imminent safety concern' }
      }.to change { BreakGlassGrant.active.count }.by(1).and change { AccessLog.where(event_type: 'break_glass').count }.by(1)

      grant = BreakGlassGrant.active.last
      expect(grant.user_id).to eq(worker.id)
      expect(grant.custom_formable_type).to eq('Client')
      expect(grant.custom_formable_id).to eq(client.id)
      expect(grant.custom_field_id).to eq(99)
      expect(grant.expires_at).to be_within(10.seconds).of(1.hour.from_now)

      log = AccessLog.where(event_type: 'break_glass').last
      expect(log.user_id).to eq(worker.id)
      expect(log.metadata['reason']).to eq('Imminent safety concern')
      expect(log.metadata['custom_field_id']).to eq(99)
      expect(log.metadata['custom_formable_type']).to eq('Client')
      expect(log.metadata['custom_formable_id']).to eq(client.id)
      expect(log.metadata['sensitivity_level']).to eq('emergency_only')
      # CONTENT-FREE: no field VALUES anywhere in the metadata.
      expect(log.metadata.values).to all(satisfy { |v| !v.to_s.match?(/given_name|family_name|date_of_birth/i) })
    end
  end

  describe 'fail-closed dual-store (bypass D)' do
    it 'ABORTS the grant when the AccessLog audit write fails (no un-audited access)' do
      worker = create(:user, :case_worker, password: password, password_confirmation: password)
      client = create(:client)
      client.users << worker
      sign_in_as(worker)

      allow(AccessLog).to receive(:create!).and_raise(StandardError, 'mongo down')

      expect {
        post break_glass_grants_path, params: { custom_formable_type: 'Client', custom_formable_id: client.id, custom_field_id: 99, reason: 'Imminent safety concern' }
      }.not_to change { BreakGlassGrant.count }
      expect(BreakGlassGrant.active.where(user_id: worker.id).count).to eq(0)
    end
  end

  describe 'cross-caseload self-elevation (LOCKED: denied)' do
    it 'denies a grant on an unreadable record and logs sensitive_field_denied' do
      worker     = create(:user, :case_worker, password: password, password_confirmation: password)
      off_client = create(:client) # NOT on worker's caseload
      sign_in_as(worker)

      expect {
        post break_glass_grants_path, params: { custom_formable_type: 'Client', custom_formable_id: off_client.id, custom_field_id: 99, reason: 'curious' }
      }.to change { AccessLog.where(event_type: 'sensitive_field_denied').count }.by(1)

      expect(BreakGlassGrant.where(user_id: worker.id, custom_formable_id: off_client.id).count).to eq(0)
      expect(AccessLog.where(event_type: 'break_glass').count).to eq(0)
    end
  end

  describe 'mandatory reason' do
    it 'denies (no grant, no break_glass row) when the reason is blank' do
      worker = create(:user, :case_worker, password: password, password_confirmation: password)
      client = create(:client)
      client.users << worker
      sign_in_as(worker)

      expect {
        post break_glass_grants_path, params: { custom_formable_type: 'Client', custom_formable_id: client.id, custom_field_id: 99, reason: '   ' }
      }.not_to change { BreakGlassGrant.count }
      expect(AccessLog.where(event_type: 'break_glass').count).to eq(0)
    end
  end
end
