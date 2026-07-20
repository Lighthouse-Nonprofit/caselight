# frozen_string_literal: true
require 'rails_helper'

# POAM-012 characterization + tripwire — Case#exit_note plaintext-at-rest.
#
# Phase 4 (FedRAMP SC-28 / SOC 2 C1.1) encrypts the exit-narrative PII on Client#exit_note (Tier 1 —
# see lib/tasks/encryption.rake ENCRYPTION_TIERS['1']['Client'] and spec/models/tier1_encryption_spec.rb).
# Case declares NO `encrypts`, so the SAME narrative — set on the exit form and, worse, copied onto every
# sibling active Case by update_cases_to_exited_from_cif via `update_all` (app/models/case.rb ~L150, which
# bypasses AR Encryption entirely) — sits in the cases.exit_note column as CLEARTEXT.
#
# This is the accepted-but-unfixed gap (POAM-012). These specs PIN current reality so that (a) a maintainer
# cannot assume exit_note is protected everywhere, and (b) an eventual "fix" that adds `encrypts :exit_note`
# to Case without a matching ENCRYPTION_TIERS entry + historical backfill + a rewrite of the update_all copy
# path trips a red test instead of silently corrupting rows once support_unencrypted_data=false.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). Case/Client saves write history docs to
# Mongo via after_save callbacks; DatabaseCleaner is active_record-only, so we clean ClientHistory ourselves.
RSpec.describe 'Case#exit_note plaintext-at-rest (POAM-012)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's accessor / transparent
  # decrypt). Same helper shape as spec/models/tier1_encryption_spec.rb.
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  after { ClientHistory.delete_all }

  describe 'declared encrypted attributes (the accepted asymmetry)' do
    it 'declares NO encrypted attributes on Case at all — POAM-012 known gap' do
      expect(Array(Case.encrypted_attributes)).to be_empty
    end

    it 'does not encrypt Case#exit_note even though Client#exit_note IS a Tier-1 encrypted column' do
      expect(Array(Case.encrypted_attributes)).not_to include(:exit_note)
      # contrast — the identical narrative field on Client is encrypted-at-rest (Tier 1).
      expect(Client.encrypted_attributes).to include(:exit_note)
    end
  end

  describe 'plaintext at rest in the raw cases.exit_note column' do
    let(:narrative) { 'Exit narrative: mother regained custody; CIF case closed 2026-07.' }

    it 'stores cases.exit_note as readable PLAINTEXT in the raw Postgres column' do
      kase = create(:case, :inactive, exit_note: narrative, exit_date: Date.today)

      # no transparent decrypt happens — the accessor and the raw column are the same cleartext.
      expect(kase.exit_note).to eq(narrative)
      expect(raw_column(Case, kase.id, :exit_note)).to eq(narrative)
    end

    it 'contrast: the same narrative on clients.exit_note is a ciphertext envelope, not plaintext' do
      client = create(:client, exit_note: narrative)

      raw = raw_column(Client, client.id, :exit_note)
      expect(raw).to be_present
      expect(raw).not_to eq(narrative)
      # it parses as an AR-Encryption message envelope (the project's own detector, encryption.rake).
      expect { ActiveRecord::Encryption.message_serializer.load(raw) }.not_to raise_error
      # transparent decrypt still round-trips on read.
      expect(Client.find(client.id).exit_note).to eq(narrative)
    end

    it 'pins the end-to-end asymmetry: identical narrative -> Client raw is ciphertext, Case raw is plaintext' do
      client = create(:client, exit_note: narrative)
      kase   = create(:case, :inactive, client: client, exit_note: narrative, exit_date: Date.today)

      expect(raw_column(Client, client.id, :exit_note)).not_to eq(narrative) # protected
      expect(raw_column(Case,   kase.id,   :exit_note)).to eq(narrative)     # NOT protected (POAM-012)
    end
  end

  describe 'update_cases_to_exited_from_cif copy path (case.rb:150 update_all)' do
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

    it 'writes the copied exit_note into the sibling raw column as PLAINTEXT (update_all bypasses AR encryption)' do
      create(:user, :fc_manager)
      foster.update(exited_from_cif: true, exit_date: Date.today, exit_note: narrative)

      # This is the landmine: if `encrypts :exit_note` is later added to Case but this update_all copy
      # remains, it will write PLAINTEXT into a now-ciphertext column instead of a ciphertext envelope.
      expect(raw_column(Case, kinship.reload.id, :exit_note)).to eq(narrative)
    end

    it 'does NOT propagate exit_note to siblings when there is no manager (guards the trigger)' do
      expect(User.managers).to be_empty # no manager created; client-factory users are 'case worker's

      foster.update(exited_from_cif: true, exit_date: Date.today, exit_note: narrative)

      expect(kinship.reload.exit_note).not_to eq(narrative)
      expect(kinship.exit_note).to be_blank
    end
  end

  describe 'drift-guard' do
    it 'tripwire: Case must not silently gain `encrypts :exit_note` while the update_all copy remains' do
      # POAM-012 is OPEN. The day someone adds `encrypts :exit_note` to Case this flips red ON PURPOSE:
      # closing the gap safely requires (a) an ENCRYPTION_TIERS registry entry (Case => [:exit_note]) in
      # lib/tasks/encryption.rake, (b) a backfill of historical plaintext rows (rake encryption:backfill),
      # and (c) replacing the case.rb:150 `update_all` copy with a callback/type-aware write — otherwise the
      # copy path silently persists plaintext into a ciphertext column (readable only while
      # support_unencrypted_data=true, corrupt once that window closes). Update this spec then.
      expect(Array(Case.encrypted_attributes)).not_to include(:exit_note),
             'Case now encrypts exit_note (POAM-012) — add the ENCRYPTION_TIERS entry, backfill historical ' \
             'rows, and fix the case.rb update_all copy path before revising this spec.'
    end
  end
end
