# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 6 (U5) — retention purges for the two change-history stores that had none.
# Invokes the REAL rake tasks (the crux logic is the floor/dry-run/confirm gating and the
# tenant iteration, not a model primitive).
RSpec.describe 'retention rake tasks' do
  before(:all) do
    Rake.application.rake_require('tasks/retention', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    # unscoped: the fixture docs carry tenant='spec-tenant', which the tenant-bound default_scope
    # (Organization.current = the test org) would MISS — scoped delete_all leaks docs across examples.
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    # The tasks iterate real Organizations; pin to the test tenant so the run is hermetic.
    allow(Organization).to receive(:pluck).with(:short_name).and_return([Apartment::Tenant.current])
  end

  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    TaskHistory.unscoped.delete_all rescue nil
    ENV.delete('DAYS'); ENV.delete('CONFIRM'); ENV.delete('TENANT')
  end

  def run_task(name)
    Rake::Task[name].reenable
    Rake::Task[name].invoke
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

    it 'CONFIRM=1 deletes only rows older than the cutoff' do
      old   = make_version(age: 4.years)
      young = make_version(age: 1.year)
      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_versions') }.to output(/DELETED=1/).to_stdout
      expect(PaperTrail::Version.exists?(old.id)).to be false
      expect(PaperTrail::Version.exists?(young.id)).to be true
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

    it 'CONFIRM=1 deletes only aged docs across both models' do
      make_history(ClientHistory, age: 4.years)
      young = make_history(ClientHistory, age: 1.day)
      make_history(TaskHistory, age: 4.years)
      ENV['DAYS'] = '1095'
      ENV['CONFIRM'] = '1'
      expect { run_task('retention:purge_client_histories') }.to output(/DELETED=1/).to_stdout
      expect(ClientHistory.unscoped.count).to eq(1)
      expect(ClientHistory.unscoped.first.id).to eq(young.id)
      expect(TaskHistory.unscoped.count).to eq(0)
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
