# lib/tasks/audit.rake
#
# AU-11 (audit record retention) — the ONE sanctioned deletion path for the
# append-only AccessLog store. Everything else (request path) is blocked by the
# model's before_update/before_destroy guards; this task deliberately uses
# delete_all to skip those guards (see docs/compliance/audit-retention.md).
#
# Safety posture:
#  - DRY-RUN by default. Deletes ONLY when CONFIRM=1 (archive-before-delete gate).
#  - DAYS (default 90) is the AU-11 online-retention floor; do not go below 90.
#
# Cross-tenant (the crux): AccessLog has a tenant-bound default_scope
# (where(tenant: Organization.current...)). In a rake context no tenant is
# switched, so Organization.current is nil and the default scope would match
# NOTHING. Retention is an org-agnostic policy, so we run UNSCOPED to span every
# tenant in the shared Mongo database in one pass, and log a per-tenant
# breakdown so the cross-tenant deletion stays auditable.

namespace :audit do
  desc "Purge AccessLog rows older than DAYS (default 90) across ALL tenants. " \
       "DRY-RUN unless CONFIRM=1. e.g. DAYS=90 CONFIRM=1 rake audit:purge"
  task purge: :environment do
    days    = Integer(ENV.fetch("DAYS", "90"))
    confirm = ENV["CONFIRM"] == "1"
    cutoff  = days.days.ago

    # unscoped => span all tenants regardless of Organization.current (nil here).
    scope = AccessLog.unscoped.older_than(days)
    total = scope.count

    Rails.logger.info(
      "[audit:purge] cutoff=#{cutoff.iso8601} days=#{days} " \
      "candidates=#{total} confirm=#{confirm}"
    )
    puts "[audit:purge] AccessLog rows older than #{days}d (created_at < #{cutoff.iso8601})"

    # Per-tenant breakdown — keeps the cross-tenant action auditable (AU-9/AU-6).
    by_tenant = Hash.new(0)
    scope.pluck(:tenant).each { |t| by_tenant[t || "(nil)"] += 1 }
    by_tenant.sort.each { |tenant, n| puts "  tenant=#{tenant} rows=#{n}" }
    puts "  TOTAL candidates=#{total}"

    if total.zero?
      puts "[audit:purge] nothing to purge."
      next
    end

    unless confirm
      puts "[audit:purge] DRY-RUN — no rows deleted. Re-run with CONFIRM=1 " \
           "AFTER the >=1yr WORM archive of this window is confirmed."
      next
    end

    # delete_all: the sanctioned callback-skipping deletion (append-only guards
    # intentionally bypassed here, and only here).
    deleted = scope.delete_all
    Rails.logger.info("[audit:purge] DELETED #{deleted} AccessLog rows (cutoff=#{cutoff.iso8601})")
    puts "[audit:purge] DELETED #{deleted} rows across #{by_tenant.size} tenant(s)."
  end
end
