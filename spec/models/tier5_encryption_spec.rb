# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 5 (FINAL) — encryption-at-rest regression specs for the polymorphic custom-form /
# program-stream JSONB `.properties` columns (FedRAMP SC-28, SOC 2 C1.1). Tier 5 is NON-DETERMINISTIC
# (fresh IV per write, like Tier 1/2): properties are never equality-matched in SQL — the advanced search
# is rewritten to in-Ruby decrypt-and-filter (see spec/classes/advanced_searches/tier5_properties_search_spec.rb).
#
# The CRUX this spec pins down: each column was widened jsonb -> :text, then `attribute :properties, :json`
# + `encrypts :properties`. We prove (a) `.properties` STILL returns a Ruby Hash on read, (b) the RAW column
# holds a ciphertext ENVELOPE (not plaintext JSON), (c) the LOAD-BEARING LANDMINE — `pluck(:properties)`
# returns the ciphertext STRING (which is why every pluck/raw-SQL consumer had to be rewritten), and (d) the
# generic update_columns backfill primitive serializes a Hash to a verifiable envelope.
#
# Runs in tenant 'app' (spec_helper switches there). CustomFieldProperty after_save :create_client_history
# writes a ClientHistory doc to Mongo for Client forms; DatabaseCleaner is active_record-only, so we clean
# ClientHistory around examples that persist a Client custom form. Mirrors spec/models/tier4_encryption_spec.rb.
RSpec.describe 'Tier 5 custom-form/program-stream JSONB properties encryption at rest (SC-28)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the decrypting attribute type)
  def raw_column(model, id, col = :properties)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  def envelope?(raw)
    return false if raw.nil?
    ActiveRecord::Encryption.message_serializer.load(raw)
    true
  rescue ActiveRecord::Encryption::Errors::Encoding,
         ActiveRecord::Encryption::Errors::ForbiddenClass,
         ActiveRecord::Encryption::Errors::Decryption # plaintext JSON Hash straggler ("hash without payload")
    false
  end

  TIER5_MODELS = [CustomFieldProperty, ClientEnrollment, ClientEnrollmentTracking, LeaveProgram].freeze

  describe 'declared encrypted attributes + widened column' do
    it 'encrypts :properties on all four models' do
      TIER5_MODELS.each do |model|
        expect(model.encrypted_attributes).to include(:properties), "#{model} is missing encrypts :properties"
      end
    end

    it 'widened :properties from jsonb to :text on all four models so the ciphertext envelope fits' do
      TIER5_MODELS.each do |model|
        expect(model.columns_hash['properties'].type).to eq(:text), "expected #{model.table_name}.properties to be :text"
      end
    end

    it 'keeps the :json attribute cast so `.properties` is a Hash on a fresh record (default {})' do
      TIER5_MODELS.each do |model|
        expect(model.new.properties).to eq({}), "expected #{model}.new.properties to default to {}"
      end
    end
  end

  describe 'CustomFieldProperty round-trip (Hash in -> envelope at rest -> Hash back)' do
    after { ClientHistory.delete_all }

    let(:client) { create(:client) }
    let(:custom_field) do
      create(:custom_field, entity_type: 'Client', form_title: 'Intake',
                            fields: [{ 'label' => 'Given Name', 'type' => 'text' },
                                     { 'label' => 'Languages', 'type' => 'select' }])
    end
    let(:props) { { 'Given Name' => 'Maria', 'Languages' => %w[English Khmer] } }

    it 'decrypts to the same Hash on read but stores a ciphertext envelope in the raw column' do
      cfp = CustomFieldProperty.create!(custom_formable: client, custom_field: custom_field, properties: props)

      reloaded = CustomFieldProperty.find(cfp.id)
      expect(reloaded.properties).to eq(props)
      expect(reloaded.properties).to be_a(Hash)
      expect(reloaded.properties['Languages']).to eq(%w[English Khmer]) # array sub-value preserved

      raw = raw_column(CustomFieldProperty, cfp.id)
      expect(raw).to be_present
      expect(envelope?(raw)).to be(true), 'expected the raw properties column to be a ciphertext envelope'
      expect(raw).not_to include('Maria'), 'plaintext leaked into the raw column'
    end

    it 'is NON-deterministic — two records with the same Hash get different envelopes (fresh IV per write)' do
      # AR dirty-tracking skips a no-op re-save (assigning the same Hash issues no UPDATE), so
      # non-determinism is shown across two SEPARATE encryptions of the same value, not a re-save of one row.
      a = CustomFieldProperty.create!(custom_formable: client, custom_field: custom_field, properties: props)
      b = CustomFieldProperty.create!(custom_formable: create(:client), custom_field: custom_field, properties: props)
      expect(raw_column(CustomFieldProperty, a.id)).not_to eq(raw_column(CustomFieldProperty, b.id))
    end
  end

  describe 'ClientEnrollment / ClientEnrollmentTracking / LeaveProgram round-trip' do
    # Empty enrollment/exit_program field defs so the partial-properties create!s below are not blocked by
    # CustomFormPresentValidator (these specs test encryption round-trip, not custom-form validation).
    let(:program_stream) { create(:program_stream, enrollment: [], exit_program: []) }
    let(:client)         { create(:client) }

    it 'ClientEnrollment stores enrollment properties as an envelope and reads back a Hash' do
      ce = create(:client_enrollment, client: client, program_stream: program_stream,
                                      properties: { 'Sponsor' => 'IRC', 'Case No' => '42' })
      expect(ClientEnrollment.find(ce.id).properties).to eq('Sponsor' => 'IRC', 'Case No' => '42')
      expect(envelope?(raw_column(ClientEnrollment, ce.id))).to be(true)
    end

    it 'ClientEnrollmentTracking stores tracking properties as an envelope and reads back a Hash' do
      ce  = create(:client_enrollment, client: client, program_stream: program_stream)
      cet = create(:client_enrollment_tracking, client_enrollment: ce,
                   tracking: create(:tracking, program_stream: program_stream, fields: []),
                   properties: { 'Weight' => '31' })
      expect(ClientEnrollmentTracking.find(cet.id).properties).to eq('Weight' => '31')
      expect(envelope?(raw_column(ClientEnrollmentTracking, cet.id))).to be(true)
    end

    it 'LeaveProgram stores exit properties as an envelope and reads back a Hash' do
      ce = create(:client_enrollment, client: client, program_stream: program_stream)
      lp = create(:leave_program, client_enrollment: ce, program_stream: program_stream,
                                  properties: { 'Exit Reason' => 'Resettled' })
      expect(LeaveProgram.find(lp.id).properties).to eq('Exit Reason' => 'Resettled')
      expect(envelope?(raw_column(LeaveProgram, lp.id))).to be(true)
    end
  end

  describe 'pluck(:properties) returns the DECRYPTED Hash (Rails 7.2 casts pluck through the encrypted type)' do
    after { ClientHistory.delete_all }

    # Rails 7.2 applies the attribute type when plucking a known column, so pluck(:properties) DECRYPTS +
    # JSON-parses to a Hash (verified live). That is why the existing pluck(:properties) consumers (the api
    # field-picker controllers, Tracking#validate_remove_field) keep working WITHOUT change — no ciphertext
    # String ever reaches them. (Earlier drafts wrongly assumed pluck bypasses the type and rewrote those
    # consumers to map(&:properties); that was unnecessary and reverted.)
    it 'reads back a Hash, so the existing pluck(:properties) consumers keep working unchanged' do
      client = create(:client)
      cf = create(:custom_field, entity_type: 'Client', form_title: 'Intake',
                                 fields: [{ 'label' => 'Given Name', 'type' => 'text' }])
      CustomFieldProperty.create!(custom_formable: client, custom_field: cf, properties: { 'Given Name' => 'Maria' })

      plucked = CustomFieldProperty.where(custom_formable: client).pluck(:properties).first
      expect(plucked).to be_a(Hash)
      expect(plucked).to eq('Given Name' => 'Maria')
    end
  end

  describe 'self.properties_by reads the DECRYPTED Hash (rewrite of the raw `-> value` SQL)' do
    after { ClientHistory.delete_all }

    it 'returns the per-record sub-values for a key, blanks removed, preserving the array contract' do
      client = create(:client)
      cf = create(:custom_field, entity_type: 'Client', form_title: 'Intake',
                                 fields: [{ 'label' => 'Given Name', 'type' => 'text' }])
      CustomFieldProperty.create!(custom_formable: client, custom_field: cf, properties: { 'Given Name' => 'Maria' })
      CustomFieldProperty.create!(custom_formable: create(:client), custom_field: cf, properties: { 'Given Name' => 'Bao' })
      CustomFieldProperty.create!(custom_formable: create(:client), custom_field: cf, properties: { 'Given Name' => '' })

      result = CustomFieldProperty.by_custom_field(cf).properties_by('Given Name')
      expect(result).to match_array(%w[Maria Bao]) # blank dropped, decrypted scalar values returned
    end
  end

  describe 'backfill primitive (update_columns) serializes the decrypted Hash to a verifiable envelope' do
    after { ClientHistory.delete_all }

    # Mirrors lib/tasks/encryption.rake#encrypt_record!: read the decrypted attr, write it straight back via
    # update_columns -> routes through the encrypted :json type -> envelope. We FIRST plant a genuine
    # PLAINTEXT JSON straggler (a pre-migration '{...}' text value, readable under support_unencrypted_data)
    # to prove the backfill upgrades it to ciphertext.
    it 'upgrades a plaintext-JSON straggler to a ciphertext envelope without firing callbacks' do
      client = create(:client)
      cf = create(:custom_field, entity_type: 'Client', form_title: 'Intake',
                                 fields: [{ 'label' => 'Given Name', 'type' => 'text' }])
      cfp = CustomFieldProperty.create!(custom_formable: client, custom_field: cf, properties: { 'Given Name' => 'Maria' })

      # plant plaintext JSON directly (bypasses the encrypting type), simulating a not-yet-backfilled row
      conn = CustomFieldProperty.connection
      conn.execute(
        "UPDATE #{conn.quote_table_name(CustomFieldProperty.table_name)} " \
        "SET properties = #{conn.quote({ 'Given Name' => 'Maria' }.to_json)} WHERE id = #{conn.quote(cfp.id)}"
      )
      expect(envelope?(raw_column(CustomFieldProperty, cfp.id))).to be(false) # straggler: not yet ciphertext

      reloaded = CustomFieldProperty.find(cfp.id)
      expect(reloaded.properties).to eq('Given Name' => 'Maria') # reads fine under support_unencrypted_data

      reloaded.update_columns(properties: reloaded.properties) # the rake's exact write
      expect(envelope?(raw_column(CustomFieldProperty, cfp.id))).to be(true) # now a verifiable envelope
    end
  end

  describe 'consumers over the decrypted Hash keep working (validators, mount_uploaders)' do
    after { ClientHistory.delete_all }

    it 'CustomFormPresentValidator still fires on a missing required custom-form value' do
      client = create(:client)
      cf = create(:custom_field, entity_type: 'Client', form_title: 'Intake',
                                 fields: [{ 'label' => 'Given Name', 'type' => 'text', 'required' => 'true' }])
      cfp = CustomFieldProperty.new(custom_formable: client, custom_field: cf, properties: { 'Given Name' => '' })
      expect(cfp).not_to be_valid
    end

    it 'the separate attachments mount_uploaders column is untouched by the properties encryption' do
      # attachments is a DISTINCT jsonb column (CarrierWave), not .properties, and not encrypted.
      expect(CustomFieldProperty.columns_hash['attachments'].type).to eq(:jsonb)
      expect(CustomFieldProperty.encrypted_attributes).not_to include(:attachments)
      expect(CustomFieldProperty.new).to respond_to(:attachments) # mount_uploaders accessor intact
    end
  end
end
