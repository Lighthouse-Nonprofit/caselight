# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 1 — field-level encryption-at-rest regression specs (FedRAMP SC-28, SOC 2 C1.1).
# Proves the 9 narrative PII columns on Client/Family/ProgressNote are encrypted (transparent decrypt
# on read; ciphertext in the raw DB column), the families.case_history column was widened to text, the
# now-unsearchable scopes were removed, and FamilyGrid no longer filters/sorts the encrypted columns.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). Client saves write a ClientHistory
# doc to Mongo via after_save :create_client_history; DatabaseCleaner is active_record-only, so we
# clean ClientHistory ourselves around examples that create Clients/ProgressNotes (default_scope is
# tenant 'app', so a plain delete_all only touches this tenant's docs).
RSpec.describe 'Tier 1 PII encryption at rest (SC-28)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's transparent decrypt)
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  describe 'declared encrypted attributes' do
    it 'encrypts the five Client narrative columns' do
      expect(Client.encrypted_attributes).to include(
        :reason_for_referral, :background, :exit_note, :rejected_note, :relevant_referral_information
      )
    end

    it 'encrypts the two Family narrative columns' do
      expect(Family.encrypted_attributes).to include(:caregiver_information, :case_history)
    end

    it 'encrypts the two ProgressNote narrative columns' do
      expect(ProgressNote.encrypted_attributes).to include(:response, :additional_note)
    end

    it 'widened families.case_history to text so non-deterministic ciphertext fits' do
      expect(Family.columns_hash['case_history'].type).to eq(:text)
    end
  end

  describe 'round-trip + raw-ciphertext (Client)' do
    after { ClientHistory.delete_all }

    it 'decrypts transparently on read but stores ciphertext in the raw column' do
      plaintext = 'Referred after a house fire; mother hospitalized.'
      client = create(:client, relevant_referral_information: plaintext, reason_for_referral: plaintext)

      # transparent decrypt on read
      reloaded = Client.find(client.id)
      expect(reloaded.relevant_referral_information).to eq(plaintext)
      expect(reloaded.reason_for_referral).to eq(plaintext)

      # raw column is ciphertext, not the plaintext
      raw = raw_column(Client, client.id, :relevant_referral_information)
      expect(raw).to be_present
      expect(raw).not_to eq(plaintext)
    end
  end

  describe 'round-trip + raw-ciphertext (Family)' do
    it 'stores caregiver_information and case_history as ciphertext' do
      family = create(:family, :kinship,
                       caregiver_information: 'Grandmother is primary caregiver.',
                       case_history: 'Opened 2026-01; reunification track.')
      reloaded = Family.find(family.id)
      expect(reloaded.caregiver_information).to eq('Grandmother is primary caregiver.')
      expect(reloaded.case_history).to eq('Opened 2026-01; reunification track.')

      expect(raw_column(Family, family.id, :caregiver_information)).not_to eq('Grandmother is primary caregiver.')
      expect(raw_column(Family, family.id, :case_history)).not_to eq('Opened 2026-01; reunification track.')
    end
  end

  describe 'round-trip + raw-ciphertext (ProgressNote)' do
    after { ClientHistory.delete_all }

    it 'stores response and additional_note as ciphertext' do
      note = create(:progress_note, response: 'Client engaged well.',
                                    additional_note: 'Follow up in two weeks.')
      reloaded = ProgressNote.find(note.id)
      expect(reloaded.response).to eq('Client engaged well.')
      expect(reloaded.additional_note).to eq('Follow up in two weeks.')
      expect(raw_column(ProgressNote, note.id, :response)).not_to eq('Client engaged well.')
      expect(raw_column(ProgressNote, note.id, :additional_note)).not_to eq('Follow up in two weeks.')
    end
  end

  describe 'dropped query sites (cannot search/sort an encrypted column)' do
    it 'removed Client.info_like' do
      expect(Client).not_to respond_to(:info_like)
    end

    it 'removed Family.caregiver_information_like and Family.case_history_like' do
      expect(Family).not_to respond_to(:caregiver_information_like)
      expect(Family).not_to respond_to(:case_history_like)
    end

    it 'FamilyGrid no longer filters caregiver_information / case_history' do
      filter_names = FamilyGrid.filters.map(&:name)
      expect(filter_names).not_to include(:caregiver_information)
      expect(filter_names).not_to include(:case_history)
    end

    it 'FamilyGrid does not ORDER BY the encrypted caregiver_information column' do
      caregiver_col = FamilyGrid.columns.find { |c| c.name == :caregiver_information }
      expect(caregiver_col).to be_present
      expect(caregiver_col.order).to be_falsey # LOWER(caregiver_information) order removed
    end
  end
end