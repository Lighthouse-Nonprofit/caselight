# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 5 — specs for the IN-RUBY decrypt-and-filter rewrite of the four `.properties` advanced-search
# builders (FedRAMP SC-28, SOC 2 C1.1). These prove the rewrite returns the SAME matched ids the old raw-JSONB
# SQL produced, across the operator x field-type matrix, and that each builder preserves its exact
# { id: '<table>.id IN (?)', values: [ids] } contract. The missing-key not_equal/is_not_empty expectations
# below were corrected to match a LIVE Postgres oracle (a `?` on a missing key is NULL and WHERE NOT NULL
# drops the row). Runs in tenant 'app'. CustomFieldProperty on a Client form writes a ClientHistory doc to
# Mongo; we clean it ourselves.
RSpec.describe 'Tier 5 in-Ruby property search rewrite', type: :model do
  # -------------------------------------------------------------------------------------------------
  # PropertiesFilter — the shared engine. Stub objects expose .properties (a Hash), exactly what the
  # builders feed it after decryption. This is the operator x type matrix proper.
  # -------------------------------------------------------------------------------------------------
  describe AdvancedSearches::PropertiesFilter do
    Rec = Struct.new(:properties)
    def rec(h) = Rec.new(h)

    def filter(field:, operator:, value:, records:, type: nil)
      described_class.new(field: field, operator: operator, value: value, type: type).select(records)
    end

    let(:scalar)   { rec('color' => 'blue') }
    let(:other)    { rec('color' => 'green') }
    let(:empty)    { rec('color' => '') }
    let(:missing)  { rec('size' => 'L') } # no 'color' key
    let(:checkbox) { rec('color' => %w[blue red]) }
    let(:num5)     { rec('age' => '5') }
    let(:num10)    { rec('age' => '10') }
    let(:numblank) { rec('age' => '') }
    let(:numjunk)  { rec('age' => 'NaN') }
    let(:d2020)    { rec('dob' => '2020-01-15') }
    let(:d2024)    { rec('dob' => '2024-06-30') }

    it 'equal: scalar equality AND checkbox-array membership (jsonb ? semantics)' do
      recs = [scalar, other, checkbox, missing]
      expect(filter(field: 'color', operator: 'equal', value: 'blue', records: recs)).to eq([scalar, checkbox])
    end

    it 'not_equal: complement over PRESENT-key rows; the missing-key row is EXCLUDED (NOT(? on NULL) is falsy)' do
      # Postgres oracle: NOT (p->\'color\' ? \'blue\') over [scalar,other,checkbox,missing] => [other].
      recs = [scalar, other, checkbox, missing]
      expect(filter(field: 'color', operator: 'not_equal', value: 'blue', records: recs)).to eq([other])
    end

    it 'contains / not_contains: case-insensitive substring on the ->> text form' do
      recs = [scalar, other, missing]
      expect(filter(field: 'color', operator: 'contains', value: 'BLU', records: recs)).to eq([scalar])
      # not_contains is NULL-propagating: the missing-key row is EXCLUDED (matches NOT ILIKE on NULL).
      expect(filter(field: 'color', operator: 'not_contains', value: 'blu', records: recs)).to eq([other])
    end

    it 'contains over a checkbox array uses the Postgres ->> spacing (["a", "b"])' do
      recs = [checkbox]
      # the serialized array text is ["blue", "red"] (space after comma) — a search for that boundary matches.
      expect(filter(field: 'color', operator: 'contains', value: '"blue", "red"', records: recs)).to eq([checkbox])
    end

    it 'is_empty / is_not_empty: the empty-string value; is_not_empty EXCLUDES the missing-key row' do
      recs = [scalar, empty, missing]
      expect(filter(field: 'color', operator: 'is_empty', value: '', records: recs)).to eq([empty])
      # Postgres oracle: NOT (p->\'color\' ? \'\') over [scalar,empty,missing] => [scalar] (missing-key dropped).
      expect(filter(field: 'color', operator: 'is_not_empty', value: '', records: recs)).to eq([scalar])
    end

    it 'ordering as STRING (default type): lexicographic, skips blank (the != "" guard)' do
      recs = [num5, num10, numblank]
      # \'5\' > \'10\' lexicographically — this is the documented TEXT behaviour when type != integer.
      expect(filter(field: 'age', operator: 'greater', value: '10', records: recs)).to eq([num5])
    end

    it 'ordering as INTEGER (type==integer): numeric, skips blank AND non-numeric' do
      recs = [num5, num10, numblank, numjunk]
      expect(filter(field: 'age', operator: 'greater', value: '6', type: 'integer', records: recs)).to eq([num10])
      expect(filter(field: 'age', operator: 'less_or_equal', value: '5', type: 'integer', records: recs)).to eq([num5])
    end

    it 'between: integer numeric inclusive, blank/non-numeric skipped' do
      recs = [num5, num10, numblank, numjunk]
      expect(filter(field: 'age', operator: 'between', value: %w[4 8], type: 'integer', records: recs)).to eq([num5])
      expect(filter(field: 'age', operator: 'between', value: %w[1 100], type: 'integer', records: recs)).to eq([num5, num10])
    end

    it 'date fields (type date) compare lexicographically == chronologically for yyyy-mm-dd' do
      recs = [d2020, d2024]
      expect(filter(field: 'dob', operator: 'greater', value: '2022-01-01', type: 'date', records: recs)).to eq([d2024])
      expect(filter(field: 'dob', operator: 'between', value: %w[2019-01-01 2021-01-01], type: 'date', records: recs)).to eq([d2020])
    end
  end

  # -------------------------------------------------------------------------------------------------
  # Builder integration — same scoping + exact return contract, against real encrypted rows.
  # -------------------------------------------------------------------------------------------------
  describe 'ClientCustomFormSqlBuilder (encrypted CustomFieldProperty)' do
    after { ClientHistory.delete_all }
    let(:form) { create(:custom_field, form_title: 'Intake', entity_type: 'Client') }

    def build(rule) = AdvancedSearches::ClientCustomFormSqlBuilder.new(form, rule).get_sql

    it 'returns clients.id IN (?) with the ids of clients whose decrypted property equals the value' do
      c1 = create(:client); c2 = create(:client)
      CustomFieldProperty.create!(custom_field: form, custom_formable: c1, properties: { 'Status' => 'Open' })
      CustomFieldProperty.create!(custom_field: form, custom_formable: c2, properties: { 'Status' => 'Closed' })

      result = build('field' => 'formbuilder_Intake_Status', 'operator' => 'equal', 'value' => 'Open', 'type' => 'text')
      expect(result[:id]).to eq('clients.id IN (?)')
      expect(result[:values]).to eq([c1.id])
    end

    it 'checkbox-array membership matches on equal' do
      c1 = create(:client)
      CustomFieldProperty.create!(custom_field: form, custom_formable: c1, properties: { 'Langs' => %w[Spanish English] })
      result = build('field' => 'formbuilder_Intake_Langs', 'operator' => 'equal', 'value' => 'English', 'type' => 'text')
      expect(result[:values]).to eq([c1.id])
    end
  end

  describe 'EnrollmentSqlBuilder (encrypted ClientEnrollment)' do
    # Non-required enrollment field so create! is not blocked by CustomFormPresentValidator (the search
    # reads the stored decrypted .properties Hash, not the program_stream field defs — so this override
    # doesn't weaken the assertion).
    let(:program) { create(:program_stream, enrollment: [{ 'label' => 'Tier', 'type' => 'text' }], exit_program: []) }

    it 'scopes to the program_stream and returns matched client_ids' do
      c1 = create(:client); c2 = create(:client)
      ClientEnrollment.create!(client: c1, program_stream: program, enrollment_date: Date.today, properties: { 'Tier' => 'A' })
      ClientEnrollment.create!(client: c2, program_stream: program, enrollment_date: Date.today, properties: { 'Tier' => 'B' })
      result = AdvancedSearches::EnrollmentSqlBuilder.new(program.id,
        'field' => 'enrollment_X_Tier', 'operator' => 'equal', 'value' => 'A', 'type' => 'text').get_sql
      expect(result).to eq(id: 'clients.id IN (?)', values: [c1.id])
    end
  end

  describe 'TrackingSqlBuilder (encrypted ClientEnrollmentTracking) — Active-enrollment filter preserved' do
    let(:program)  { create(:program_stream) }
    # Non-required tracking field so the CET create! is not blocked by CustomFormPresentValidator.
    let(:tracking) { create(:tracking, program_stream: program, fields: [{ 'label' => 'Score', 'type' => 'text' }]) }

    it 'only considers trackings whose enrollment is Active, client_id read through the join' do
      c_active = create(:client); c_exited = create(:client)
      e_active = ClientEnrollment.create!(client: c_active, program_stream: program, enrollment_date: Date.today, status: 'Active')
      e_exited = ClientEnrollment.create!(client: c_exited, program_stream: program, enrollment_date: Date.today, status: 'Exited')
      ClientEnrollmentTracking.create!(client_enrollment: e_active, tracking: tracking, properties: { 'Score' => '7' })
      ClientEnrollmentTracking.create!(client_enrollment: e_exited, tracking: tracking, properties: { 'Score' => '7' })

      result = AdvancedSearches::TrackingSqlBuilder.new(tracking.id,
        'field' => 'tracking_X_Score', 'operator' => 'equal', 'value' => '7', 'type' => 'text').get_sql
      expect(result[:id]).to eq('clients.id IN (?)')
      expect(result[:values]).to eq([c_active.id]) # exited enrollment's tracking excluded
    end
  end

  describe 'ExitProgramSqlBuilder (encrypted LeaveProgram) — reproduces legacy always-TEXT compare' do
    # Non-required exit_program field so the LeaveProgram create! is not blocked by the present-validator.
    let(:program) { create(:program_stream, exit_program: [{ 'label' => 'Reason', 'type' => 'text' }], enrollment: []) }

    it 'returns matched client_ids through the client_enrollment join' do
      c1 = create(:client)
      e1 = ClientEnrollment.create!(client: c1, program_stream: program, enrollment_date: Date.today)
      LeaveProgram.create!(client_enrollment: e1, program_stream: program, exit_date: Date.today, properties: { 'Reason' => 'Graduated' })
      result = AdvancedSearches::ExitProgramSqlBuilder.new(program.id,
        'field' => 'exitprogram_X_Reason', 'operator' => 'equal', 'value' => 'Graduated').get_sql
      expect(result[:id]).to eq('clients.id IN (?)')
      expect(result[:values]).to eq([c1.id])
    end
  end
end
