# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 6 (U5) — retention purges for the two change-history stores that had none.
# Invokes the REAL rake tasks (the crux logic is the floor/dry-run/confirm gating and the
# tenant iteration, not a model primitive).
#
# POAM-015 (closed): CONFIRM=1 purges are ARCHIVE-GATED — they refuse without a VERIFIED
# archive-manifest entry and delete AT the manifest's cutoff. Each example points ARCHIVE_DIR at
# its own tmpdir; archive_and_verify! runs the real archive + verify tasks.
RSpec.describe 'retention rake tasks' do
  before(:all) do
    Rake.application.rake_require('tasks/retention', [Rails.root.join('lib').to_s])
    Rake.application.rake_require('tasks/audit',     [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    # unscoped: the fixture docs carry tenant='spec-tenant', which the tenant-bound default_scope
    # (Organization.current = the test org) would MISS — scoped delete_all leaks docs across examples.
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    # The tasks iterate real Organizations; pin to the test tenant so the run is hermetic.
    allow(Organization).to receive(:pluck).with(:short_name).and_return([Apartment::Tenant.current])
    @archive_dir = Dir.mktmpdir('retention-spec-archives')
    ENV['ARCHIVE_DIR'] = @archive_dir
  end

  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    FileUtils.remove_entry(@archive_dir) if @archive_dir && Dir.exist?(@archive_dir)
    ENV.delete('DAYS'); ENV.delete('CONFIRM'); ENV.delete('TENANT')
    ENV.delete('ARCHIVE_DIR'); ENV.delete('AUDIT_DAYS'); ENV.delete('ALL')
  end

  def run_task(name)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  end

  # Run the real archive + verify pipeline (quietly), preserving the caller's DAYS/CONFIRM intent.
  def archive_and_verify!(days: '1095', audit_days: '90')
    saved = { 'DAYS' => ENV['DAYS'], 'CONFIRM' => ENV['CONFIRM'] }
    ENV['DAYS'] = days
    ENV['AUDIT_DAYS'] = audit_days
    ENV.delete('CONFIRM')
    expect { run_task('retention:archive') }.to output(/retention:archive/).to_stdout
    expect { run_task('retention:verify_archive') }.to output(/PASS/).to_stdout
  ensure
    saved.each { |k, v| v.nil? ? ENV.delete(k) : ENV[k] = v }
  end

  def manifest
    JSON.parse(File.read(File.join(@archive_dir, 'manifest.json')))
  end

  def make_version(age:)
    v = PaperTrail::Version.create!(item_type: 'Client', item_id: 999_999, event: 'update', whodunnit: 'spec')
    v.update_columns(created_at: age.ago)
    v
  end

  def make_history(model, age:)
    doc = model.unscoped.create!(tenant: 'spec-tenant', object: { 'id' => 1 })
    doc.set(created_at: age.ago)
    doc
  end

  describe 'retention:purge_versions' do
    it 'refuses DAYS below the 365-day floor' do
      ENV['DAYS'] = '30'
      expect { run_task('retention:purge_versions') }.to raise_error(SystemExit)
    end

    it 'dry-run deletes nothing' do
      old = make_version(age: 4.years)
      ENV['DAYS'] = '1095'
      expect { run_task('retention:purge_versions') }.to output(/candidates=1/).to_stdout
      expect(PaperTrail::Version.exists?(old.id)).to be true
    end

    it 'CONFIRM=1 REFUSES without a verified archive (the POAM-015 gate)' do
      old = make_version(age: 4.years)
      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_versions') }.to raise_error(SystemExit)
      expect(PaperTrail::Version.exists?(old.id)).to be true # nothing deleted on refusal
    end

    it 'CONFIRM=1 deletes archived-and-verified rows, keeping younger ones' do
      old   = make_version(age: 4.years)
      young = make_version(age: 1.year)
      archive_and_verify!

      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_versions') }.to output(/DELETED=1/).to_stdout
      expect(PaperTrail::Version.exists?(old.id)).to be false
      expect(PaperTrail::Version.exists?(young.id)).to be true
    end

    it 'deletes AT the verified manifest cutoff, never the requested one' do
      archived = make_version(age: 5.years)
      archive_and_verify!(days: '1460')            # verified window: rows older than ~4 years
      unarchived = make_version(age: 1278.days)    # ~3.5y: purge-eligible at DAYS=1095, NOT archived
                                                   # (integer days: whenever's Numeric patch breaks 3.5.years)

      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_versions') }.to output(/DELETED=1/).to_stdout
      expect(PaperTrail::Version.exists?(archived.id)).to be false
      expect(PaperTrail::Version.exists?(unarchived.id)).to be true # awaits the next archive
    end

    it 'REFUSES when gated candidates exceed the archived rows (a write backdated after archive)' do
      make_version(age: 4.years)
      archive_and_verify!
      make_version(age: 4.years)                   # backdated INTO the verified window post-archive

      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_versions') }.to raise_error(SystemExit)
      expect(PaperTrail::Version.where(item_id: 999_999).count).to eq(2) # nothing deleted
    end

    it 'skips tenants excluded by TENANT=' do
      old = make_version(age: 4.years)
      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      ENV['TENANT'] = 'some-other-tenant'
      expect { run_task('retention:purge_versions') }.to raise_error(SystemExit) # no matching tenant
      expect(PaperTrail::Version.exists?(old.id)).to be true
    end
  end

  describe 'retention:purge_client_histories' do
    it 'refuses DAYS below the floor' do
      ENV['DAYS'] = '90'
      expect { run_task('retention:purge_client_histories') }.to raise_error(SystemExit)
    end

    it 'dry-run reports per-tenant candidates and deletes nothing' do
      make_history(ClientHistory, age: 4.years)
      make_history(TaskHistory,   age: 4.years)
      ENV['DAYS'] = '1095'
      expect { run_task('retention:purge_client_histories') }
        .to output(/ClientHistory: TOTAL candidates=1.*tenant=spec-tenant rows=1/m).to_stdout
      expect(ClientHistory.unscoped.count).to eq(1)
      expect(TaskHistory.unscoped.count).to eq(1)
    end

    it 'CONFIRM=1 REFUSES without a verified archive (the POAM-015 gate)' do
      make_history(ClientHistory, age: 4.years)
      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_client_histories') }.to raise_error(SystemExit)
      expect(ClientHistory.unscoped.count).to eq(1)
    end

    it 'CONFIRM=1 deletes archived-and-verified docs across both models, keeping younger ones' do
      make_history(ClientHistory, age: 4.years)
      young = make_history(ClientHistory, age: 1.day)
      make_history(TaskHistory, age: 4.years)
      archive_and_verify!

      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_client_histories') }.to output(/DELETED=1/).to_stdout
      expect(ClientHistory.unscoped.count).to eq(1)
      expect(ClientHistory.unscoped.first.id).to eq(young.id)
      expect(TaskHistory.unscoped.count).to eq(0)
    end
  end

  describe 'retention:archive + retention:verify_archive (POAM-015)' do
    it 'archives eligible rows per store as gzip JSONL with an unverified manifest entry' do
      make_version(age: 4.years)
      make_history(ClientHistory, age: 4.years)

      ENV['DAYS'] = '1095'
      expect { run_task('retention:archive') }
        .to output(/versions\/#{Apartment::Tenant.current}: archived 1 row|archived 1 row/).to_stdout

      entries = manifest
      version_key = entries.keys.find { |k| k.start_with?("versions|#{Apartment::Tenant.current}|") }
      expect(version_key).to be_present
      expect(entries[version_key]['rows']).to eq(1)
      expect(entries[version_key]['verified_at']).to be_nil
      file = File.join(@archive_dir, entries[version_key]['file'])
      expect(File).to exist(file)
      expect(Zlib::GzipReader.open(file) { |gz| gz.each_line.count }).to eq(1)
    end

    it 'verify stamps verified_at on a clean entry and FAILS on a tampered file' do
      make_version(age: 4.years)
      ENV['DAYS'] = '1095'
      expect { run_task('retention:archive') }.to output(/archived/).to_stdout
      expect { run_task('retention:verify_archive') }.to output(/PASS/).to_stdout
      key = manifest.keys.find { |k| k.start_with?('versions|') }
      expect(manifest[key]['verified_at']).to be_present

      # Tamper the archive file: re-verify with ALL=1 must fail (sha mismatch) and exit 1.
      path = File.join(@archive_dir, manifest[key]['file'])
      Zlib::GzipWriter.open(path) { |gz| gz.puts('{"tampered":true}') }
      ENV['ALL'] = '1'
      expect { run_task('retention:verify_archive') }.to raise_error(SystemExit)
    end

    it 'is idempotent per (store, tenant, cutoff): nothing to archive writes no entry' do
      expect { run_task('retention:archive') }.to output(/0 rows — no archive written/).to_stdout
      expect(File.exist?(File.join(@archive_dir, 'manifest.json'))).to be false
    end
  end

  describe 'audit:purge (POAM-015 gate + the 90-day floor it was missing)' do
    def make_log(age:)
      log = AccessLog.unscoped.new(event_type: 'read', tenant: 'spec-tenant')
      log.save!(validate: false)
      AccessLog.collection.update_one({ _id: log.id }, { '$set' => { 'created_at' => age.ago.utc } })
      log
    end

    before(:each) { AccessLog.unscoped.delete_all rescue nil }
    after(:each)  { AccessLog.unscoped.delete_all rescue nil }

    it 'refuses DAYS below the 90-day AU-11 floor' do
      ENV['DAYS'] = '30'
      expect { run_task('audit:purge') }.to raise_error(SystemExit)
    end

    it 'CONFIRM=1 REFUSES without a verified archive' do
      make_log(age: 2.years)
      ENV['DAYS'] = '90'
      ENV['CONFIRM'] = '1'
      expect { run_task('audit:purge') }.to raise_error(SystemExit)
      expect(AccessLog.unscoped.count).to eq(1)
    end

    it 'CONFIRM=1 deletes archived-and-verified rows, keeping younger ones' do
      make_log(age: 2.years)
      young = make_log(age: 10.days)
      archive_and_verify!

      ENV['DAYS'] = '90'
      ENV['CONFIRM'] = '1'
      expect { run_task('audit:purge') }.to output(/DELETED 1 rows/).to_stdout
      expect(AccessLog.unscoped.count).to eq(1)
      expect(AccessLog.unscoped.first.id).to eq(young.id)
    end
  end

  describe 'retention:report' do
    it 'prints age buckets for versions and the Mongo stores without mutating anything' do
      make_version(age: 2.years)
      make_history(ClientHistory, age: 30.days)
      expect { run_task('retention:report') }
        .to output(/paper_trail versions.*Mongo history stores/m).to_stdout
      expect(PaperTrail::Version.where(item_id: 999_999).count).to eq(1)
      expect(ClientHistory.unscoped.count).to eq(1)
    end
  end
end
