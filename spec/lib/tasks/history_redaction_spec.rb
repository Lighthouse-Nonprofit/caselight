# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 6 (U4) — the one-time scrub of PRE-EXISTING history rows (POAM-SC28-HIST close-out).
# Contract: dry-run touches nothing; CONFIRM redacts exactly the skip-listed keys (who/when +
# non-PII keys survive); re-run is a no-op; verify passes after and FAILS before; Mongo docs lose
# the denylisted paths (top-level + embedded).
RSpec.describe 'history redaction rake tasks' do
  before(:all) do
    Rake.application.rake_require('tasks/history_redaction', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    allow(Organization).to receive(:pluck).with(:short_name).and_return([Apartment::Tenant.current])
  end

  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    ENV.delete('CONFIRM'); ENV.delete('TENANT')
  end

  def run_task(name)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
  end

  # A pre-U2 version row: full plaintext YAML payloads, written straight to the columns
  # (update_columns bypasses the model layer exactly like the legacy writer did).
  def plant_legacy_version!
    v = PaperTrail::Version.create!(item_type: 'Client', item_id: 424_242, event: 'update', whodunnit: 'legacy')
    v.update_columns(
      object: YAML.dump({ 'id' => 424_242, 'given_name' => 'LegacyName', 'status' => 'Referred',
                          'current_address' => 'LEGACY_ADDR' }),
      object_changes: YAML.dump({ 'given_name' => ['LegacyName', 'NewName'], 'status' => %w[Referred Accepted] })
    )
    v
  end

  describe 'history:scrub_versions + verify_versions' do
    it 'dry-run reports but writes nothing, and verify FAILS while plaintext remains' do
      v = plant_legacy_version!
      expect { run_task('history:scrub_versions') }.to output(/candidates=1/).to_stdout
      expect(v.reload.object).to include('LegacyName')
      expect { run_task('history:verify_versions') }.to raise_error(SystemExit)
    end

    it 'CONFIRM=1 strips exactly the skip-listed keys and keeps who/when + non-PII; verify passes; re-run no-op' do
      v = plant_legacy_version!
      ENV['CONFIRM'] = '1'
      expect { run_task('history:scrub_versions') }.to output(/REDACTED=1/).to_stdout

      v.reload
      expect(v.object).not_to include('LegacyName')
      expect(v.object).not_to include('LEGACY_ADDR')
      expect(v.object).to include('status')
      expect(v.object_changes).not_to include('NewName')
      expect(v.object_changes).to include('Accepted') # non-PII change kept
      expect(v.whodunnit).to eq('legacy')

      # The payload still parses through the app's ladder (same-format YAML re-serialize).
      expect(SafeVersionValue.parse(v.object)).to include('status' => 'Referred')

      expect { run_task('history:verify_versions') }.to output(/PASS/).to_stdout

      expect { run_task('history:scrub_versions') }.to output(/REDACTED=0/).to_stdout
    ensure
      PaperTrail::Version.where(item_id: 424_242).delete_all
    end
  end

  describe 'history:scrub_client_histories + verify_client_histories' do
    it 'unsets top-level and embedded PII paths, then verify passes; dry-run writes nothing' do
      doc = ClientHistory.unscoped.new(tenant: 'legacy-tenant',
                                       object: { 'id' => 9, 'given_name' => 'MongoLegacy', 'status' => 'Referred' })
      doc.case_worker_client_histories.build(object: { 'id' => 2, 'email' => 'staff@x.test', 'roles' => 'admin' })
      doc.save!(validate: false)

      run_task('history:scrub_client_histories') # dry-run
      expect(ClientHistory.unscoped.where('object.given_name' => { '$exists' => true }).count).to eq(1)
      expect { run_task('history:verify_client_histories') }.to raise_error(SystemExit)

      ENV['CONFIRM'] = '1'
      run_task('history:scrub_client_histories')

      fresh = ClientHistory.unscoped.find(doc.id)
      expect(fresh.object.keys).to include('id', 'status')
      expect(fresh.object.keys).not_to include('given_name')
      staff = fresh.case_worker_client_histories.first
      expect(staff.object.keys).to include('id', 'roles')
      expect(staff.object.keys).not_to include('email')

      expect { run_task('history:verify_client_histories') }.to output(/PASS/).to_stdout
    end
  end
end
