# frozen_string_literal: true
require "rails_helper"

# Component C — AU-11 retention selection logic, tested at the MODEL level
# (not by shelling out to the rake task) so it is fast and deterministic.
#
# Mongo is NOT auto-cleaned (DatabaseCleaner is active_record-only), so we clean
# AccessLog ourselves before/after. delete_all skips the append-only callbacks
# (intended -- same path the purge uses).
#
# Suite context: before(:each) switches to tenant "app", so the AccessLog tenant
# default resolves to "app". We deliberately also create rows for another tenant
# to prove the cross-tenant purge semantics.
RSpec.describe AccessLog, type: :model do
  # unscoped: cleanup must span tenants — these specs create tenant:"other" rows,
  # and a tenant-scoped delete_all (default_scope = current tenant "app") would
  # leave them to leak into the next example (off-by-N on the purge count).
  before(:each) { AccessLog.unscoped.delete_all }
  after(:each)  { AccessLog.unscoped.delete_all }

  # Helper: create a row, then stamp created_at via a raw collection update on
  # _id so the aged timestamp is the asserted value REGARDLESS of
  # Mongoid::Timestamps::Created behavior. The raw update bypasses the
  # append-only before_update callback, exactly like the sanctioned purge does.
  def make_log(created_at:, tenant: "app", event_type: "read")
    log = AccessLog.create!(
      tenant:     tenant,
      event_type: event_type,
      controller: "clients",
      action:     "show"
    )
    AccessLog.collection.update_one({ _id: log.id }, { "$set" => { created_at: created_at.utc } })
    log.reload
  end

  describe ".older_than" do
    it "selects only rows whose created_at is strictly older than N days" do
      old_row    = make_log(created_at: 100.days.ago)
      recent_row = make_log(created_at: 10.days.ago)

      ids = AccessLog.older_than(90).pluck(:id)

      expect(ids).to include(old_row.id)
      expect(ids).not_to include(recent_row.id)
    end

    it "treats the boundary as strict (a row near the cutoff resolves cleanly)" do
      just_old = make_log(created_at: 90.days.ago - 1.hour)
      just_new = make_log(created_at: 90.days.ago + 1.hour)

      ids = AccessLog.older_than(90).pluck(:id)

      expect(ids).to include(just_old.id)
      expect(ids).not_to include(just_new.id)
    end

    it "honors a custom day window" do
      row = make_log(created_at: 40.days.ago)

      expect(AccessLog.older_than(30).pluck(:id)).to include(row.id)
      expect(AccessLog.older_than(60).pluck(:id)).not_to include(row.id)
    end

    it "coerces a string DAYS value (rake passes ENV strings)" do
      old_row = make_log(created_at: 100.days.ago)
      expect(AccessLog.older_than("90").pluck(:id)).to include(old_row.id)
    end
  end

  describe "cross-tenant purge semantics" do
    it "default_scope hides other tenants, but .unscoped spans all tenants" do
      app_old   = make_log(created_at: 100.days.ago, tenant: "app")
      other_old = make_log(created_at: 100.days.ago, tenant: "other")

      # Default-scoped (current tenant == "app") sees only the app row.
      scoped_ids = AccessLog.older_than(90).pluck(:id)
      expect(scoped_ids).to include(app_old.id)
      expect(scoped_ids).not_to include(other_old.id)

      # Unscoped (the path the rake purge uses) spans both tenants.
      unscoped_ids = AccessLog.unscoped.older_than(90).pluck(:id)
      expect(unscoped_ids).to include(app_old.id, other_old.id)
    end

    it "the sanctioned purge (unscoped + delete_all) removes aged rows across every tenant" do
      app_old    = make_log(created_at: 100.days.ago, tenant: "app")
      other_old  = make_log(created_at: 100.days.ago, tenant: "other")
      app_recent = make_log(created_at: 5.days.ago,  tenant: "app")

      deleted = AccessLog.unscoped.older_than(90).delete_all

      expect(deleted).to eq(2)
      expect(AccessLog.unscoped.where(id: app_old.id)).to be_empty
      expect(AccessLog.unscoped.where(id: other_old.id)).to be_empty
      # recent row survives the purge
      expect(AccessLog.unscoped.where(id: app_recent.id).count).to eq(1)
    end

    it "in a rake-like context (nil tenant => default scope matches nothing) the purge must use unscoped" do
      make_log(created_at: 100.days.ago, tenant: "app")
      make_log(created_at: 100.days.ago, tenant: "other")

      # Simulate the rake context: default_scope keyed on a nil current tenant.
      no_tenant = AccessLog.where(tenant: nil).older_than(90)
      expect(no_tenant.count).to eq(0)

      # Unscoped is the correct, documented path and finds both.
      expect(AccessLog.unscoped.older_than(90).count).to eq(2)
    end
  end
end
