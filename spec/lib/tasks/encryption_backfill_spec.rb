# frozen_string_literal: true
require 'rails_helper'

# Phase 4 — encryption:backfill / encryption:verify LOGIC, exercised at the MODEL level (NOT by
# shelling the rake) so it is fast and deterministic, mirroring spec/models/access_log_retention_spec.rb.
# We drive the EXACT primitives the rake uses:
#   * backfill = read decrypted/plaintext attr, then update_columns(col => value) -> routes through
#                the AR::Encryption type's #serialize -> ciphertext, WITHOUT validations /
#                after_save :create_client_history / paper_trail Versions / touch.
#   * verify   = read the RAW stored value (bypassing the decrypting type) and confirm it round-trips
#                through the encrypted type (deserialize); a value that raises is a plaintext straggler.
#
# Runs in tenant 'app' (spec_helper switches there). support_unencrypted_data=true (the test
# initializer) is what lets us PLANT genuine plaintext via raw SQL to simulate a pre-migration row
# and still READ it through the model. Mongo (ClientHistory) is cleaned around each example.
RSpec.describe 'encryption backfill + verify logic', type: :model do
  before(:each) { ClientHistory.delete_all }
  after(:each)  { ClientHistory.delete_all }

  TIER1 = {
    Client       => %i[reason_for_referral background exit_note rejected_note relevant_referral_information],
    Family       => %i[caregiver_information case_history],
    ProgressNote => %i[response additional_note]
  }.freeze

  # ---- the rake's primitives, inlined so the spec proves the real logic ----

  # Same write the rake's encrypt_record! performs per row.
  def backfill_row(record, columns)
    attrs = columns.each_with_object({}) { |c, h| h[c] = record.public_send(c) }
    record.update_columns(attrs)
  end

  def raw_value(model, id, column)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(column)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  # Plant genuine PLAINTEXT into an encrypted column (a pre-migration straggler), bypassing the
  # encrypting type. update_columns would encrypt, so we go straight to SQL.
  def plant_plaintext(model, id, column, value)
    conn = model.connection
    conn.execute(
      "UPDATE #{conn.quote_table_name(model.table_name)} " \
      "SET #{conn.quote_column_name(column)} = #{conn.quote(value)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  # Mirrors encryption.rake#ciphertext? — true iff the encrypted type can decrypt the raw value
  # (blank/NULL = nothing stored = not a straggler).
  def ciphertext?(model, column, raw)
    return true if raw.nil? || raw == ''
    model.type_for_attribute(column.to_s).deserialize(raw)
    true
  rescue ActiveRecord::Encryption::Errors::Base
    false
  end

  describe 'Tier 1 columns are declared encrypted (else backfill would write plaintext)' do
    it 'declares `encrypts` for every Tier 1 column' do
      TIER1.each do |model, columns|
        declared = model.encrypted_attributes.to_a
        columns.each { |c| expect(declared).to include(c), "#{model}.#{c} is not `encrypts`-declared" }
      end
    end
  end

  describe 'backfill encrypts a pre-migration plaintext row (round-trip)' do
    it 'converts planted Client plaintext to ciphertext while preserving the value' do
      client = create(:client)
      secret = 'Referred after a domestic-violence incident; mother fled with two children.'

      # Pre-migration state: raw plaintext on disk (bypassing the encrypting type).
      plant_plaintext(Client, client.id, :relevant_referral_information, secret)
      planted = raw_value(Client, client.id, :relevant_referral_information)
      expect(planted).to eq(secret)
      expect(ciphertext?(Client, :relevant_referral_information, planted)).to be(false)

      # support_unencrypted_data=true lets the model still read it during the window.
      expect(Client.find(client.id).relevant_referral_information).to eq(secret)

      # backfill via the rake's mechanism.
      backfill_row(Client.find(client.id), TIER1[Client])

      raw = raw_value(Client, client.id, :relevant_referral_information)
      expect(raw).not_to eq(secret)
      expect(ciphertext?(Client, :relevant_referral_information, raw)).to be(true)
      expect(Client.find(client.id).relevant_referral_information).to eq(secret) # decrypts back
    end

    it 'encrypts all Tier 1 columns on Family and ProgressNote too' do
      family = create(:family, :kinship,
                       caregiver_information: 'Grandmother is primary caregiver.',
                       case_history: 'Opened 2024; two prior placements.')
      note = create(:progress_note,
                    response: 'Family stable; no concerns this visit.',
                    additional_note: 'Follow up re: school enrollment.')

      [[Family, family], [ProgressNote, note]].each do |model, record|
        TIER1[model].each { |c| plant_plaintext(model, record.id, c, "plain-#{c}") }
        backfill_row(model.find(record.id), TIER1[model])
        TIER1[model].each do |c|
          expect(ciphertext?(model, c, raw_value(model, record.id, c))).to be(true), "#{model}.#{c} not encrypted"
          expect(model.find(record.id).public_send(c)).to eq("plain-#{c}")
        end
      end
    end
  end

  describe 'idempotency' do
    it 're-running over an already-encrypted row is a value-preserving no-op' do
      client = create(:client, background: 'Arrived 2023 via refugee resettlement.')
      backfill_row(Client.find(client.id), TIER1[Client])             # first pass
      first_raw = raw_value(Client, client.id, :background)
      expect(ciphertext?(Client, :background, first_raw)).to be(true)

      backfill_row(Client.find(client.id), TIER1[Client])             # second pass
      second_raw = raw_value(Client, client.id, :background)
      expect(ciphertext?(Client, :background, second_raw)).to be(true)
      # Non-deterministic => ciphertext differs each write, but the value round-trips.
      expect(Client.find(client.id).background).to eq('Arrived 2023 via refugee resettlement.')
    end
  end

  describe 'side-effect safety (the reason we use update_columns, not save!)' do
    it 'does not create a ClientHistory (after_save :create_client_history) on backfill' do
      client = create(:client)
      ClientHistory.delete_all # ignore the create-time history
      expect { backfill_row(Client.find(client.id), TIER1[Client]) }.not_to change(ClientHistory, :count)
    end

    it 'does not write a paper_trail Version on backfill' do
      client = create(:client)
      expect { backfill_row(Client.find(client.id), TIER1[Client]) }
        .not_to change { PaperTrail::Version.where(item_type: 'Client', item_id: client.id).count }
    end
  end

  describe 'verify detects a planted plaintext straggler' do
    after { ClientHistory.delete_all }

    it 'flags a column that is still plaintext and passes once encrypted' do
      client = create(:client)
      column = :exit_note

      # Freshly created => already ciphertext => verify passes.
      expect(ciphertext?(Client, column, raw_value(Client, client.id, column))).to be(true)

      # Plant plaintext => verify must FAIL for this column.
      plant_plaintext(Client, client.id, column, 'Case closed: family relocated out of county.')
      expect(ciphertext?(Client, column, raw_value(Client, client.id, column))).to be(false)

      # Backfill => verify passes again.
      backfill_row(Client.find(client.id), TIER1[Client])
      expect(ciphertext?(Client, column, raw_value(Client, client.id, column))).to be(true)
    end

    it 'treats blank ("") and NULL as non-stragglers (nothing sensitive stored)' do
      client = create(:client)
      plant_plaintext(Client, client.id, :rejected_note, '')
      expect(ciphertext?(Client, :rejected_note, raw_value(Client, client.id, :rejected_note))).to be(true)
    end
  end
end