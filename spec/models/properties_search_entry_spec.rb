# frozen_string_literal: true

require 'rails_helper'

# POAM-024 — the deterministic search-entry sidecar (PR A1: schema + models + write path).
#
# Proves the three load-bearing properties of the design:
#   1. NORMALIZATION mirrors AdvancedSearches::PropertiesFilter#member? exactly (the oracle-verified
#      jsonb `?` semantics): scalars/arrays/''/nil/[]/absent keys/duplicate elements.
#   2. The after_save DIFF-SYNC is idempotent BY CONSTRUCTION — a second pass over unchanged data
#      performs zero writes (row ids AND updated_at byte-stable). This is what makes the PR-A2
#      every-deploy backfill provably idempotent (the #203 standard).
#   3. The rows are real deterministic-encryption citizens: ciphertext-equality queryable via
#      where(value:), envelope at rest, NULL presence markers, FK-cascade cleanup, and NO audit
#      side effects (no paper_trail versions, no Mongo history) from entry writes.
#
# CustomFieldProperty on a Client form writes a ClientHistory doc to Mongo; we clean it ourselves
# (tier5_properties_search_spec precedent).
RSpec.describe 'POAM-024 properties search-entry sidecar', type: :model do
  after { ClientHistory.delete_all }

  let(:form)   { create(:custom_field, form_title: 'Sidecar Intake', entity_type: 'Client') }
  let(:client) { create(:client) }

  def create_cfp(props)
    CustomFieldProperty.create!(custom_field: form, custom_formable: client, properties: props)
  end

  def entry_pairs(cfp)
    CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
                                  .map { |e| [e.field_label, e.value] }
  end

  # ------------------------------------------------------------------------------------------------
  # 1. Normalization — pure function, asserted against the member? contract.
  # ------------------------------------------------------------------------------------------------
  describe '#properties_search_desired_pairs (member? parity)' do
    def pairs_for(props)
      CustomFieldProperty.new(properties: props).properties_search_desired_pairs.to_a
    end

    it 'scalar -> one row of its to_s form (numbers included — member? compares to_s)' do
      expect(pairs_for('A' => 'x')).to match_array([%w[A x]])
      expect(pairs_for('N' => 7)).to match_array([['N', '7']])
    end

    it 'array -> one row per DISTINCT element.to_s; a JSON null element -> "" (nil.to_s parity)' do
      expect(pairs_for('B' => %w[b1 b2])).to match_array([%w[B b1], %w[B b2]])
      expect(pairs_for('B' => %w[dup dup])).to match_array([%w[B dup]])
      expect(pairs_for('B' => ['b1', nil])).to match_array([%w[B b1], ['B', '']])
    end

    it "empty-string scalar -> a '' row (what is_empty probes)" do
      expect(pairs_for('C' => '')).to match_array([['C', '']])
    end

    it 'nil scalar and [] -> one NULL presence-marker row (key present, matches no equality probe)' do
      expect(pairs_for('D' => nil)).to match_array([['D', nil]])
      expect(pairs_for('E' => [])).to match_array([['E', nil]])
    end

    it 'absent keys contribute nothing; non-Hash properties -> empty set' do
      expect(pairs_for({})).to eq([])
      expect(CustomFieldProperty.new.properties_search_desired_pairs.to_a).to eq([])
    end
  end

  # ------------------------------------------------------------------------------------------------
  # 2. The after_save diff-sync.
  # ------------------------------------------------------------------------------------------------
  describe 'after_save diff-sync' do
    it 'materializes one entry per pair on create, presence markers included' do
      cfp = create_cfp('A' => 'x', 'B' => %w[b1 b2], 'C' => '', 'D' => nil, 'E' => [])
      expect(entry_pairs(cfp)).to match_array(
        [%w[A x], %w[B b1], %w[B b2], ['C', ''], ['D', nil], ['E', nil]]
      )
    end

    it 'update touches ONLY the delta — surviving rows keep their ids (no rewrite churn)' do
      cfp = create_cfp('A' => 'x', 'B' => %w[b1 b2])
      surviving_ids = CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
                                                    .reject { |e| e.value == 'b2' }.map(&:id).sort

      cfp.update!(properties: { 'A' => 'x', 'B' => %w[b1], 'F' => 'new' })

      rows = CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id).to_a
      expect(rows.map { |e| [e.field_label, e.value] })
        .to match_array([%w[A x], %w[B b1], %w[F new]])
      kept = rows.reject { |e| e.field_label == 'F' }.map(&:id).sort
      expect(kept).to eq(surviving_ids)
    end

    it 'is a ZERO-WRITE no-op over unchanged data (ids and updated_at byte-stable) — the idempotence contract' do
      cfp = create_cfp('A' => 'x', 'B' => %w[b1 b2], 'D' => nil)
      before = CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
                                             .order(:id).map { |e| [e.id, e.updated_at] }

      delta = cfp.sync_properties_search_entries!

      after = CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
                                            .order(:id).map { |e| [e.id, e.updated_at] }
      expect(delta).to eq(added: 0, removed: 0)
      expect(after).to eq(before)
    end

    it 'repairs hand-made duplicates and strays on the next sync' do
      cfp = create_cfp('A' => 'x')
      CustomFieldPropertySearchEntry.create!(custom_field_property_id: cfp.id, field_label: 'A', value: 'x')   # dup
      CustomFieldPropertySearchEntry.create!(custom_field_property_id: cfp.id, field_label: 'Z', value: 'gone') # stray

      delta = cfp.sync_properties_search_entries!

      expect(delta).to eq(added: 0, removed: 2)
      expect(entry_pairs(cfp)).to match_array([%w[A x]])
    end

    it 'does not fire when a save changes nothing Tier-5 (saved_change_to_properties? gate)' do
      cfp = create_cfp('A' => 'x')
      expect(cfp).not_to receive(:sync_properties_search_entries!)
      cfp.touch
    end
  end

  # ------------------------------------------------------------------------------------------------
  # 3. Deterministic-encryption citizenship + lifecycle + audit silence.
  # ------------------------------------------------------------------------------------------------
  describe 'deterministic queryability and storage' do
    it 'where(value:) finds rows by ciphertext equality (ExtendedDeterministicQueries)' do
      cfp = create_cfp('A' => 'findme')
      scope = CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
      expect(scope.where(value: 'findme').count).to eq(1)
      expect(scope.where(value: 'other').count).to eq(0)
    end

    it 'stores an AR-Encryption envelope at rest, never plaintext' do
      cfp = create_cfp('A' => 'plainly-visible')
      raw = CustomFieldPropertySearchEntry.connection.select_value(
        "SELECT value FROM custom_field_property_search_entries WHERE custom_field_property_id = #{cfp.id}"
      )
      expect(raw).not_to include('plainly-visible')
      expect(raw).to start_with('{') # the base64 JSON envelope {"p":..,"h":..}
    end
  end

  describe 'lifecycle and audit silence' do
    it 'FK-cascades entries on a RAW owner delete (no callback required)' do
      cfp = create_cfp('A' => 'x')
      expect(CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)).to exist
      cfp.delete # no callbacks — the DB constraint must do the work
      expect(CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)).not_to exist
    end

    it 'entry writes create no paper_trail versions and no extra Mongo history' do
      cfp = create_cfp('A' => 'x')
      versions_before  = PaperTrail::Version.count
      histories_before = ClientHistory.count

      cfp.update!(properties: { 'A' => 'x', 'B' => 'y' }) # owner version is EXPECTED (redacted)…
      owner_versions = PaperTrail::Version.count - versions_before

      CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id).delete_all
      cfp.sync_properties_search_entries! # …but pure entry rebuilds add NOTHING
      expect(PaperTrail::Version.count - versions_before).to eq(owner_versions)
      expect(PaperTrail::Version.where(item_type: 'CustomFieldPropertySearchEntry')).not_to exist
      expect(ClientHistory.count - histories_before).to be <= 1 # only the owner-save hook, never entries
    end
  end

  # ------------------------------------------------------------------------------------------------
  # The other three Tier-5 owners ride the same concern — smoke each write path.
  # ------------------------------------------------------------------------------------------------
  describe 'the other three Tier-5 owners' do
    let(:program) do
      create(:program_stream, enrollment: [{ 'label' => 'Tier', 'type' => 'text' }],
                              exit_program: [{ 'label' => 'Reason', 'type' => 'text' }])
    end
    let(:enrollment) do
      ClientEnrollment.create!(client: client, program_stream: program,
                               enrollment_date: Date.today, properties: { 'Tier' => 'A' })
    end

    it 'ClientEnrollment syncs' do
      expect(ClientEnrollmentSearchEntry.where(client_enrollment_id: enrollment.id)
                                        .map { |e| [e.field_label, e.value] }).to eq([%w[Tier A]])
    end

    it 'ClientEnrollmentTracking syncs' do
      tracking = create(:tracking, program_stream: program,
                                   fields: [{ 'label' => 'Score', 'type' => 'text' }])
      cet = ClientEnrollmentTracking.create!(client_enrollment: enrollment, tracking: tracking,
                                             properties: { 'Score' => '7' })
      expect(ClientEnrollmentTrackingSearchEntry.where(client_enrollment_tracking_id: cet.id)
                                                .map { |e| [e.field_label, e.value] }).to eq([%w[Score 7]])
    end

    it 'LeaveProgram syncs' do
      lp = LeaveProgram.create!(client_enrollment: enrollment, program_stream: program,
                                exit_date: Date.today, properties: { 'Reason' => 'moved' })
      expect(LeaveProgramSearchEntry.where(leave_program_id: lp.id)
                                    .map { |e| [e.field_label, e.value] }).to eq([%w[Reason moved]])
    end
  end
end
