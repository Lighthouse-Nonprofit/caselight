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
  # This whole file exercises the MIGRATION-WINDOW machinery: it plants genuine plaintext and reads
  # it back through models, exactly what the real rake tasks do — and since the 2026-07-26
  # strict-mode cutover those tasks re-enable plaintext tolerance for their own process. Mirror
  # that here; every other spec runs strict.
  around(:each) do |example|
    ActiveRecord::Encryption.config.support_unencrypted_data = true
    example.run
  ensure
    ActiveRecord::Encryption.config.support_unencrypted_data = false
  end

  before(:each) { ClientHistory.delete_all }
  after(:each)  { ClientHistory.delete_all }

  TIER1 = {
    Case         => %i[exit_note],
    Client       => %i[reason_for_referral background exit_note rejected_note relevant_referral_information],
    Family       => %i[caregiver_information case_history],
    ProgressNote => %i[response additional_note]
  }.freeze

  # ---- the rake's primitives, inlined so the spec proves the real logic ----

  # Same write the rake's encrypt_record! performs per row. read_attribute, NOT public_send:
  # a reader override (Client's Tier-4 ignore_case names prefer the nil-until-reencrypt
  # original_* sidecar) must never leak into what gets written back. And a column that reads
  # nil while the stored value is non-NULL is a failed read, not a nil value — skip it rather
  # than overwrite ciphertext with NULL (2026-07-22 pilot-box incident).
  def backfill_row(record, columns)
    attrs = columns.each_with_object({}) do |c, h|
      value = record.read_attribute(c)
      next if value.nil? && !record.read_attribute_before_type_cast(c).nil?
      h[c] = value
    end
    record.update_columns(attrs) if attrs.any?
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

  # Mirrors encryption.rake#ciphertext? — true iff the raw value parses as an AR-Encryption message
  # envelope. NOT type#deserialize: support_unencrypted_data=true makes deserialize tolerate plaintext
  # (returns it, no raise), so it can't detect a straggler. The envelope parse is key-independent and
  # tier-agnostic (deterministic + non-deterministic share the envelope format).
  def ciphertext?(_model, _column, raw)
    return true if raw.nil? || raw == ''
    ActiveRecord::Encryption.message_serializer.load(raw)
    true
  rescue ActiveRecord::Encryption::Errors::Encoding, ActiveRecord::Encryption::Errors::ForbiddenClass
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

    it 'converts a planted pre-migration Case exit_note (the POAM-012 copy) to ciphertext' do
      kase   = create(:case, :inactive)
      secret = 'Exited to permanent housing; sponsor family assumed ongoing support.'

      plant_plaintext(Case, kase.id, :exit_note, secret)
      expect(ciphertext?(Case, :exit_note, raw_value(Case, kase.id, :exit_note))).to be(false)
      expect(Case.find(kase.id).exit_note).to eq(secret) # readable during the migration window

      backfill_row(Case.find(kase.id), TIER1[Case])

      raw = raw_value(Case, kase.id, :exit_note)
      expect(raw).not_to eq(secret)
      expect(ciphertext?(Case, :exit_note, raw)).to be(true)
      expect(Case.find(kase.id).exit_note).to eq(secret) # decrypts back
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

  # 2026-07-22 pilot-box incident: the Tier-4 backfill ran on rows whose ignore_case original_*
  # sidecars were still NULL (reencrypt_client_names hadn't run). Reading via public_send went
  # through the ignore_case reader override -> nil sidecar -> update_columns wrote NULL over
  # every name ciphertext. These examples pin the two defenses: read the COLUMN, and never
  # replace a non-NULL stored value with NULL.
  describe 'Tier-4 regression: backfill on a pre-reencrypt row must not destroy names' do
    # Mirrors ENCRYPTION_TIERS['4'] (registry contents are guarded by encryption_registry_spec).
    TIER4 = %i[given_name family_name local_given_name local_family_name
               original_given_name original_family_name
               original_local_given_name original_local_family_name].freeze

    def nil_sidecars!(client)
      # Simulate a legacy row the reencrypt task hasn't reached: main columns encrypted,
      # original_* sidecars NULL. (update_columns(nil) => NULL; no type round-trip needed.)
      client.update_columns(
        original_given_name: nil, original_family_name: nil,
        original_local_given_name: nil, original_local_family_name: nil
      )
    end

    it 'preserves the name columns even though the model reader blanks (the incident repro)' do
      client = create(:client, given_name: 'Yusuf', family_name: 'Hassan')
      nil_sidecars!(client)

      record = Client.find(client.id)
      expect(record.given_name).to be_nil                                # the reader override trap
      expect(record.read_attribute(:given_name)).to be_present           # the data is still there

      backfill_row(record, TIER4)

      survivor = Client.find(client.id)
      expect(survivor.read_attribute(:given_name)).to be_present
      expect(survivor.read_attribute(:given_name)).to eq('yusuf')        # ignore_case stores downcased
      expect(survivor.read_attribute(:family_name)).to eq('hassan')
      expect(raw_value(Client, client.id, :given_name)).not_to be_nil
    end

    it 'refuses to overwrite a non-NULL stored value when the column reads nil' do
      client = create(:client, given_name: 'Amina', family_name: 'Hassan')
      raw_before = raw_value(Client, client.id, :given_name)
      expect(raw_before).not_to be_nil

      record = Client.find(client.id)
      allow(record).to receive(:read_attribute).and_wrap_original do |m, *args|
        args.first.to_s == 'given_name' ? nil : m.call(*args)
      end

      backfill_row(record, TIER4)

      expect(raw_value(Client, client.id, :given_name)).not_to be_nil
      expect(Client.find(client.id).read_attribute(:given_name)).to eq('amina')
    end

    it 'the rake itself reads via read_attribute with the nil-guard (drift guard vs this spec)' do
      src = File.read(Rails.root.join('lib/tasks/encryption.rake'))
      helper = src[/def encrypt_record!.*?^  end/m]
      expect(helper).to include('read_attribute'), 'encrypt_record! must read the column, not the reader'
      expect(helper).not_to include('public_send')
      expect(helper).to include('read_attribute_before_type_cast'), 'encrypt_record! lost its nil-guard'

      reencrypt = src[/task reencrypt_client_names:.*?^  end/m]
      expect(reencrypt).to include('read_attribute_before_type_cast'), 'reencrypt_client_names lost its nil-guard'
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

    it 'does not fire Case after_save callbacks or write a Version on the Case backfill (POAM-012)' do
      kase = create(:case, :inactive)
      ClientHistory.delete_all # ignore the create-time history
      expect { backfill_row(Case.find(kase.id), TIER1[Case]) }
        .not_to change { PaperTrail::Version.where(item_type: 'Case', item_id: kase.id).count }
      expect(ClientHistory.count).to eq(0) # after_save :create_client_history did not fire
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