# frozen_string_literal: true

require 'rails_helper'
require 'rake'

# POAM-024 (PR A2) — runs the REAL properties_search:backfill / :verify tasks, TWICE (the #203
# standard: a deploy-time rewrite must prove idempotence across two consecutive runs, byte-identical,
# because bootstrap re-runs step 7d on EVERY deploy). Test env has the single 'app' tenant
# (encryption_reencrypt_names_spec precedent).
#
# The byte-identical assertion snapshots (id, field_label, RAW ciphertext, created_at, updated_at)
# straight from Postgres — a second run that "harmlessly rewrote" rows would trip it, exactly the
# failure mode the 2026-07-23 incident taught us to fear.
RSpec.describe 'properties_search:backfill + :verify (real rake, run twice)' do
  before(:all) do
    Rake.application.rake_require('tasks/properties_search', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  around(:each) do |example|
    example.run
  ensure
    # The backfill task re-enables plaintext tolerance for its own process (mirroring
    # encryption:backfill); every other spec runs strict — restore.
    ActiveRecord::Encryption.config.support_unencrypted_data = false
    %w[CONFIRM TENANT BATCH RESET].each { |k| ENV.delete(k) }
    FileUtils.rm_f(Rails.root.join('tmp', 'properties_search_backfill_progress.json'))
  end

  before(:each) { ClientHistory.delete_all }
  after(:each)  { ClientHistory.delete_all }

  ENTRY_TABLES = %w[custom_field_property_search_entries client_enrollment_search_entries
                    client_enrollment_tracking_search_entries leave_program_search_entries].freeze

  def run_backfill(confirm: true)
    confirm ? ENV['CONFIRM'] = '1' : ENV.delete('CONFIRM')
    ENV['TENANT'] = 'app'
    Rake::Task['properties_search:backfill'].reenable
    Rake::Task['properties_search:backfill'].invoke
  end

  def run_verify
    ENV['TENANT'] = 'app'
    Rake::Task['properties_search:verify'].reenable
    Rake::Task['properties_search:verify'].invoke
  end

  def connection = ActiveRecord::Base.connection

  # The full byte-level state of every entry table: raw ciphertext, ids, timestamps.
  def snapshot
    ENTRY_TABLES.flat_map do |table|
      connection.select_rows(
        "SELECT id, field_label, value, created_at, updated_at FROM #{table} ORDER BY id"
      ).map { |row| [table, *row] }
    end
  end

  def wipe_entries!
    ENTRY_TABLES.each { |table| connection.execute("DELETE FROM #{table}") }
  end

  # One record on each of the four Tier-5 models; the CFP carries the full normalization matrix
  # (scalar / array / '' / nil / []), so run 1 must create 6 + 1 + 1 + 1 = 9 entries over 4 records.
  def seed_full_matrix!
    form    = create(:custom_field, form_title: 'Rake Matrix', entity_type: 'Client')
    client  = create(:client)
    cfp     = CustomFieldProperty.create!(
      custom_field: form, custom_formable: client,
      properties: { 'A' => 'x', 'B' => %w[b1 b2], 'C' => '', 'D' => nil, 'E' => [] }
    )
    program = create(:program_stream, enrollment: [{ 'label' => 'Tier', 'type' => 'text' }],
                                      exit_program: [{ 'label' => 'Reason', 'type' => 'text' }])
    enrollment = ClientEnrollment.create!(client: client, program_stream: program,
                                          enrollment_date: Date.today, properties: { 'Tier' => 'A' })
    tracking = create(:tracking, program_stream: program,
                                 fields: [{ 'label' => 'Score', 'type' => 'text' }])
    ClientEnrollmentTracking.create!(client_enrollment: enrollment, tracking: tracking,
                                     properties: { 'Score' => '7' })
    LeaveProgram.create!(client_enrollment: enrollment, program_stream: program,
                         exit_date: Date.today, properties: { 'Reason' => 'moved' })
    cfp
  end

  it 'run 1 rebuilds, run 2 is byte-identical with a zero delta, verify PASSes' do
    seed_full_matrix!
    wipe_entries! # force run 1 to do the real work (the callbacks built these on create)

    expect { run_backfill }.to output(/TOTAL records=\d+ added=9 removed=0/).to_stdout
    first = snapshot
    expect(first.size).to eq(9)

    # THE contract: run 2 reports zero AND changed no byte (ids, ciphertext, created/updated_at).
    expect { run_backfill }.to output(/TOTAL records=\d+ added=0 removed=0/).to_stdout
    expect(snapshot).to eq(first)

    expect { run_verify }.to output(/PASS/).to_stdout
  end

  it 'converges after drift (exactly the delta), then back to zero' do
    cfp = seed_full_matrix!
    # Simulate drift: one entry lost, one stray planted.
    CustomFieldPropertySearchEntry.where(custom_field_property_id: cfp.id)
                                  .where.not(value: nil).first.delete
    CustomFieldPropertySearchEntry.create!(custom_field_property_id: cfp.id,
                                           field_label: 'Stray', value: 'zzz')

    expect { run_backfill }.to output(/TOTAL records=\d+ added=1 removed=1/).to_stdout
    expect { run_backfill }.to output(/TOTAL records=\d+ added=0 removed=0/).to_stdout
    expect { run_verify }.to output(/PASS/).to_stdout
  end

  it 'DRY-RUN (no CONFIRM) reports the pending work but writes nothing' do
    seed_full_matrix!
    wipe_entries!

    expect { run_backfill(confirm: false) }
      .to output(/added=9 removed=0 \(DRY-RUN, nothing written\)/).to_stdout
    expect(snapshot).to be_empty
  end

  it 'verify FAILs loud (non-zero exit) on planted drift — the bootstrap 7d gate' do
    cfp = seed_full_matrix!
    CustomFieldPropertySearchEntry.create!(custom_field_property_id: cfp.id,
                                           field_label: 'Stray', value: 'zzz')

    expect {
      expect { run_verify }.to output(/sidecar drift/).to_stdout
    }.to raise_error(SystemExit)
  end
end
