# frozen_string_literal: true
require 'rails_helper'

# POAM-012 CLOSED — Case#exit_note is encrypted at rest (Tier 1).
#
# Phase 4 (FedRAMP SC-28 / SOC 2 C1.1) encrypted the exit-narrative PII on Client#exit_note; Case
# carries a point-in-time COPY of the same narrative (set on the exit form and fanned onto every
# sibling active Case by update_cases_to_exited_from_cif). POAM-012 closed the gap: Case declares
# `encrypts :exit_note` (registered under ENCRYPTION_TIERS['1']['Case'] in lib/tasks/encryption.rake,
# historical rows backfilled at deploy by encryption:backfill), and the copy path writes per-record
# via update_columns — NOT update_all, which would bypass AR Encryption and persist plaintext into
# the ciphertext column.
#
# These specs prove the fix end to end and drift-guard the two load-bearing details: the ciphertext
# envelope in the raw column (both write paths), and the copy path staying off update_all.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). Case/Client saves write history docs to
# Mongo via after_save callbacks; DatabaseCleaner is active_record-only, so we clean ClientHistory ourselves.
RSpec.describe 'Case#exit_note encrypted-at-rest (POAM-012)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's accessor / transparent
  # decrypt). Same helper shape as spec/models/tier1_encryption_spec.rb.
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  # the project's own envelope detector shape (lib/tasks/encryption.rake ciphertext?).
  def ciphertext_envelope?(raw)
    ActiveRecord::Encryption.message_serializer.load(raw)
    true
  rescue ActiveRecord::Encryption::Errors::Encoding,
         ActiveRecord::Encryption::Errors::ForbiddenClass,
         ActiveRecord::Encryption::Errors::Decryption
    false
  end

  after { ClientHistory.delete_all }

  describe 'declared encrypted attributes' do
    it 'encrypts Case#exit_note, symmetric with the Tier-1 Client#exit_note' do
      expect(Case.encrypted_attributes).to include(:exit_note)
      expect(Client.encrypted_attributes).to include(:exit_note)
    end
  end

  describe 'ciphertext at rest in the raw cases.exit_note column' do
    let(:narrative) { 'Exit narrative: mother regained custody; CIF case closed 2026-07.' }

    it 'stores cases.exit_note as a ciphertext envelope and round-trips on read' do
      kase = create(:case, :inactive, exit_note: narrative, exit_date: Date.today)

      raw = raw_column(Case, kase.id, :exit_note)
      expect(raw).to be_present
      expect(raw).not_to eq(narrative)
      expect(ciphertext_envelope?(raw)).to be(true)
      # transparent decrypt still round-trips on read.
      expect(Case.find(kase.id).exit_note).to eq(narrative)
    end

    it 'protects the identical narrative on BOTH stores (the POAM-012 asymmetry is gone)' do
      client = create(:client, exit_note: narrative)
      kase   = create(:case, :inactive, client: client, exit_note: narrative, exit_date: Date.today)

      expect(raw_column(Client, client.id, :exit_note)).not_to eq(narrative)
      expect(raw_column(Case,   kase.id,   :exit_note)).not_to eq(narrative)
    end
  end

  describe 'update_cases_to_exited_from_cif copy path (per-record update_columns)' do
    # Mirrors the existing after_save exit-flow setup in spec/models/case_spec.rb: the propagation branch
    # fires only when a manager exists (User.managers.any?). The default client-factory user is a
    # 'case worker', so a manager is present ONLY in the examples that create one.
    let!(:client)  { create(:client) }
    let!(:foster)  { create(:case, case_type: 'FC', client: client) }
    let!(:kinship) { create(:case, case_type: 'KC', client: client) }
    let(:narrative) { 'Family relocated out of state; all active cases closed at CIF exit.' }

    it 'copies exit_note onto sibling active cases when exited_from_cif is set' do
      create(:user, :fc_manager)
      foster.update(exited_from_cif: true, exit_date: Date.today, exit_note: narrative)

      expect(kinship.reload.exit_note).to eq(narrative)
    end

    it 'writes the copied exit_note into the sibling raw column as CIPHERTEXT (update_columns routes through AR encryption)' do
      create(:user, :fc_manager)
      foster.update(exited_from_cif: true, exit_date: Date.today, exit_note: narrative)

      raw = raw_column(Case, kinship.reload.id, :exit_note)
      expect(raw).not_to eq(narrative)
      expect(ciphertext_envelope?(raw)).to be(true)
    end

    it 'does NOT propagate exit_note to siblings when there is no manager (guards the trigger)' do
      expect(User.managers).to be_empty # no manager created; client-factory users are 'case worker's

      foster.update(exited_from_cif: true, exit_date: Date.today, exit_note: narrative)

      expect(kinship.reload.exit_note).not_to eq(narrative)
      expect(kinship.exit_note).to be_blank
    end
  end

  describe 'drift-guards' do
    it 'keeps the copy path off update_all (a bulk write would bypass AR encryption)' do
      src    = File.read(Rails.root.join('app/models/case.rb'))
      method = src[/def update_cases_to_exited_from_cif.*?^  end/m]
      expect(method).to be_present
      code = method.lines.reject { |l| l.strip.start_with?('#') }.join # judge code, not comments
      expect(code).to include('update_columns'), 'the exited_from_cif fan-out must write per-record'
      expect(code).not_to include('update_all'),
             'update_all bypasses AR Encryption and would persist plaintext exit_note (POAM-012)'
    end

    it 'scrubs exit_note out of embedded Case history snapshots (HistoryPiiFilter derives from encrypts)' do
      expect(HistoryPiiFilter.scrub_keys_for(Case)).to include('exit_note')
    end
  end
end
