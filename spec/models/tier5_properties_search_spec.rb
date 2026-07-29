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

  # -------------------------------------------------------------------------------------------------
  # POAM-024 (PR A3) — the sidecar read path. Every operator class runs through BOTH paths against
  # REAL encrypted rows and must return the same client ids as the legacy in-Ruby engine (which the
  # oracle matrix above pins to the original SQL). Plus: the equality path must never decrypt, and
  # shadow mode must serve legacy while logging a values-free divergence event.
  # -------------------------------------------------------------------------------------------------
  describe 'sidecar read path (POAM-024 A3)' do
    after { ClientHistory.delete_all }

    def with_sidecar_mode(mode)
      previous = Rails.application.config.x.tier5_sidecar_search
      Rails.application.config.x.tier5_sidecar_search = mode
      yield
    ensure
      Rails.application.config.x.tier5_sidecar_search = previous
    end

    let(:form) { create(:custom_field, form_title: 'Sidecar Parity', entity_type: 'Client') }

    def cfp!(client, props)
      CustomFieldProperty.create!(custom_field: form, custom_formable: client, properties: props)
    end

    def search(rule)
      AdvancedSearches::ClientCustomFormSqlBuilder.new(form, rule).get_sql[:values].sort
    end

    def parity!(rule, expected_clients)
      expected = expected_clients.map(&:id).sort
      legacy   = with_sidecar_mode(:off) { search(rule) }
      sidecar  = with_sidecar_mode(:on)  { search(rule) }
      expect(legacy).to  eq(expected), "legacy path diverged for #{rule['operator']}"
      expect(sidecar).to eq(expected), "sidecar path diverged for #{rule['operator']}"
    end

    it 'equality family: scalar equal, array membership, missing-key not_equal exclusion, is_empty/is_not_empty' do
      c_scalar  = create(:client); c_other = create(:client); c_checkbox = create(:client)
      c_empty   = create(:client); c_missing = create(:client)
      cfp!(c_scalar,   'Color' => 'blue')
      cfp!(c_other,    'Color' => 'green')
      cfp!(c_checkbox, 'Color' => %w[blue red])
      cfp!(c_empty,    'Color' => '')
      cfp!(c_missing,  'Size'  => 'L') # no Color key

      base = { 'field' => 'formbuilder_X_Color', 'type' => 'text' }
      parity!(base.merge('operator' => 'equal',        'value' => 'blue'), [c_scalar, c_checkbox])
      parity!(base.merge('operator' => 'not_equal',    'value' => 'blue'), [c_other, c_empty]) # missing-key EXCLUDED
      parity!(base.merge('operator' => 'is_empty',     'value' => ''),     [c_empty])
      parity!(base.merge('operator' => 'is_not_empty', 'value' => ''),     [c_scalar, c_other, c_checkbox])
    end

    it 'residual operators: contains/not_contains and integer ordered/between (presence-prefiltered Ruby)' do
      c5 = create(:client); c10 = create(:client); c_blank = create(:client); c_missing = create(:client)
      cfp!(c5,      'Age' => '5',  'Note' => 'blue sky')
      cfp!(c10,     'Age' => '10', 'Note' => 'green field')
      cfp!(c_blank, 'Age' => '',   'Note' => '')
      cfp!(c_missing, 'Other' => 'x')

      note = { 'field' => 'formbuilder_X_Note', 'type' => 'text' }
      parity!(note.merge('operator' => 'contains',     'value' => 'BLU'), [c5])
      parity!(note.merge('operator' => 'not_contains', 'value' => 'blu'), [c10, c_blank]) # missing-key EXCLUDED

      age = { 'field' => 'formbuilder_X_Age', 'type' => 'integer' }
      parity!(age.merge('operator' => 'greater', 'value' => '6'),        [c10])
      parity!(age.merge('operator' => 'between', 'value' => %w[4 7]),    [c5])
    end

    it 'enrollment / tracking / exit builders return identical ids under :on (pluck-through-join swap)' do
      program = create(:program_stream, enrollment: [{ 'label' => 'Tier', 'type' => 'text' }],
                                        exit_program: [{ 'label' => 'Reason', 'type' => 'text' }])
      tracking = create(:tracking, program_stream: program, fields: [{ 'label' => 'Score', 'type' => 'text' }])
      c1 = create(:client); c2 = create(:client)
      e1 = ClientEnrollment.create!(client: c1, program_stream: program, enrollment_date: Date.today,
                                    status: 'Active', properties: { 'Tier' => 'A' })
      ClientEnrollment.create!(client: c2, program_stream: program, enrollment_date: Date.today,
                               status: 'Active', properties: { 'Tier' => 'B' })
      ClientEnrollmentTracking.create!(client_enrollment: e1, tracking: tracking, properties: { 'Score' => '7' })
      LeaveProgram.create!(client_enrollment: e1, program_stream: program, exit_date: Date.today,
                           properties: { 'Reason' => 'Graduated' })

      {
        AdvancedSearches::EnrollmentSqlBuilder =>
          [program.id, { 'field' => 'enrollment_X_Tier', 'operator' => 'equal', 'value' => 'A', 'type' => 'text' }],
        AdvancedSearches::ExitProgramSqlBuilder =>
          [program.id, { 'field' => 'exitprogram_X_Reason', 'operator' => 'equal', 'value' => 'Graduated' }]
      }.each do |builder, (arg, rule)|
        off = with_sidecar_mode(:off) { builder.new(arg, rule).get_sql[:values].sort }
        on  = with_sidecar_mode(:on)  { builder.new(arg, rule).get_sql[:values].sort }
        expect(on).to eq(off), "#{builder} diverged"
        expect(on).to eq([c1.id])
      end

      # Tracking separately: e1's LeaveProgram flipped it to Exited, so re-activate for the assertion.
      e1.update_columns(status: 'Active')
      rule = { 'field' => 'tracking_X_Score', 'operator' => 'equal', 'value' => '7', 'type' => 'text' }
      off = with_sidecar_mode(:off) { AdvancedSearches::TrackingSqlBuilder.new(tracking.id, rule).get_sql[:values] }
      on  = with_sidecar_mode(:on)  { AdvancedSearches::TrackingSqlBuilder.new(tracking.id, rule).get_sql[:values] }
      expect(on).to eq(off)
      expect(on).to eq([c1.id])
    end

    it 'the equality path NEVER decrypts (no match? call) under :on' do
      client = create(:client)
      cfp!(client, 'Color' => 'blue')
      filter = AdvancedSearches::PropertiesFilter.new(field: 'Color', operator: 'equal',
                                                      value: 'blue', type: 'text')
      allow(filter).to receive(:match?).and_raise('decrypt path used on an equality operator')

      ids = with_sidecar_mode(:on) do
        filter.apply(CustomFieldProperty.where(custom_field_id: form.id)).pluck(:custom_formable_id)
      end
      expect(ids).to eq([client.id])
    end

    it 'shadow mode serves LEGACY results and logs ONE values-free divergence event when the sidecar drifts' do
      AccessLog.delete_all
      client = create(:client)
      record = cfp!(client, 'Color' => 'blue')
      # Corrupt the sidecar so the two paths disagree (simulates a missed write, the exact case
      # shadow exists to catch).
      CustomFieldPropertySearchEntry.where(custom_field_property_id: record.id).delete_all

      rule = { 'field' => 'formbuilder_X_Color', 'operator' => 'equal', 'value' => 'blue', 'type' => 'text' }
      result = with_sidecar_mode(:shadow) { search(rule) }
      expect(result).to eq([client.id]) # legacy (correct) result served

      events = AccessLog.where(event_type: 'tier5_sidecar_shadow').to_a
      expect(events.size).to eq(1)
      meta = events.first.metadata
      expect(meta['owner_model']).to eq('CustomFieldProperty')
      expect(meta['operator']).to eq('equal')
      expect(meta['legacy_count']).to eq(1)
      expect(meta['sidecar_count']).to eq(0)
      # VALUES-FREE: never the label, never the probed value.
      expect(meta.values.join).not_to include('Color', 'blue')
    ensure
      AccessLog.delete_all
    end

    it 'shadow mode logs nothing when the paths agree' do
      AccessLog.delete_all
      client = create(:client)
      cfp!(client, 'Color' => 'blue')

      rule = { 'field' => 'formbuilder_X_Color', 'operator' => 'equal', 'value' => 'blue', 'type' => 'text' }
      result = with_sidecar_mode(:shadow) { search(rule) }
      expect(result).to eq([client.id])
      expect(AccessLog.where(event_type: 'tier5_sidecar_shadow').count).to eq(0)
    ensure
      AccessLog.delete_all
    end
  end
end
