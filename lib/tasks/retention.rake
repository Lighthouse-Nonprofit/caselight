# lib/tasks/retention.rake
#
# Phase 6 — data-lifecycle retention for the two CHANGE-HISTORY stores that had none:
#
#   * paper_trail `versions`      — per-tenant Postgres (Apartment schema each). Unbounded until now
#                                   (PaperTrail.config.version_limit is nil BY DESIGN — a per-record
#                                   cap silently deletes history; age-based retention is this task's job).
#   * Mongo ClientHistory/TaskHistory — shared database, tenant-scoped only by the `tenant` field
#                                   (same topology as AccessLog; see audit.rake, whose cross-tenant
#                                   idiom purge_client_histories mirrors).
#
# Policy: docs/compliance/policies/data-retention.md. AccessLog retention stays in audit.rake (AU-11).
#
# Safety posture (mirrors audit.rake / encryption.rake):
#  - DRY-RUN by default; deletes ONLY when CONFIRM=1.
#  - HARD FLOOR: DAYS < 365 is refused outright. Change audit is a SECURITY.md commitment; deleting
#    young versions would undermine AU-family evidence. The floor is code, not convention.
#  - NOT scheduled: the verified-archive-before-purge precondition (audit-retention.md POA&M) is not
#    code-enforced yet, so every purge stays a deliberate operator action.

namespace :retention do
  RETENTION_FLOOR_DAYS = 365

  def retention_days!(task)
    days = Integer(ENV.fetch("DAYS", RETENTION_FLOOR_DAYS.to_s))
    if days < RETENTION_FLOOR_DAYS
      abort "[#{task}] REFUSED: DAYS=#{days} is below the #{RETENTION_FLOOR_DAYS}-day retention floor " \
            "(change-audit evidence; see docs/compliance/policies/data-retention.md)."
    end
    days
  end

  desc "Purge paper_trail versions older than DAYS (default/floor #{RETENTION_FLOOR_DAYS}) per tenant. " \
       "DRY-RUN unless CONFIRM=1. Optional TENANT=short_name. e.g. DAYS=1095 CONFIRM=1 rake retention:purge_versions"
  task purge_versions: :environment do
    days    = retention_days!("retention:purge_versions")
    confirm = ENV["CONFIRM"] == "1"
    cutoff  = days.days.ago

    tenants = Organization.pluck(:short_name)
    tenants &= [ENV["TENANT"]] if ENV["TENANT"].present?
    abort "[retention:purge_versions] no matching tenant" if tenants.empty?

    puts "[retention:purge_versions] versions older than #{days}d (created_at < #{cutoff.iso8601}) confirm=#{confirm}"
    grand_total = 0
    tenants.sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        scope = PaperTrail::Version.where("created_at < ?", cutoff)
        count = scope.count
        grand_total += count
        puts "  tenant=#{tenant} candidates=#{count}"
        next if count.zero? || !confirm

        deleted = 0
        scope.in_batches(of: 1_000) { |batch| deleted += batch.delete_all }
        Rails.logger.info("[retention:purge_versions] tenant=#{tenant} DELETED #{deleted} versions (cutoff=#{cutoff.iso8601})")
        puts "  tenant=#{tenant} DELETED=#{deleted}"
      end
    end
    puts "  TOTAL candidates=#{grand_total}"
    puts "[retention:purge_versions] DRY-RUN — nothing deleted. Re-run with CONFIRM=1 AFTER the archive of this window is confirmed." unless confirm
  end

  desc "Purge Mongo ClientHistory/TaskHistory older than DAYS (default/floor #{RETENTION_FLOOR_DAYS}) across ALL tenants " \
       "(shared Mongo, audit.rake idiom). DRY-RUN unless CONFIRM=1."
  task purge_client_histories: :environment do
    days    = retention_days!("retention:purge_client_histories")
    confirm = ENV["CONFIRM"] == "1"
    cutoff  = days.days.ago

    puts "[retention:purge_client_histories] history docs older than #{days}d (created_at < #{cutoff.iso8601}) confirm=#{confirm}"
    [ClientHistory, TaskHistory].each do |model|
      # unscoped => span all tenants regardless of Organization.current (nil in a rake context —
      # the tenant-bound default_scope would otherwise match nothing). Deliberate cross-tenant
      # exception, same as audit:purge; retention is a uniform org-agnostic policy.
      scope = model.unscoped.where(:created_at.lt => cutoff)
      total = scope.count

      by_tenant = Hash.new(0)
      scope.pluck(:tenant).each { |t| by_tenant[t || "(nil)"] += 1 }
      puts "  #{model.name}: TOTAL candidates=#{total}"
      by_tenant.sort.each { |tenant, n| puts "    tenant=#{tenant} rows=#{n}" }
      next if total.zero? || !confirm

      deleted = scope.delete_all
      Rails.logger.info("[retention:purge_client_histories] #{model.name} DELETED #{deleted} docs (cutoff=#{cutoff.iso8601})")
      puts "  #{model.name}: DELETED=#{deleted} across #{by_tenant.size} tenant(s)"
    end
    puts "[retention:purge_client_histories] DRY-RUN — nothing deleted. Re-run with CONFIRM=1 AFTER archive." unless confirm
  end

  desc "Read-only age-bucket report over versions (per tenant), ClientHistory/TaskHistory and AccessLog."
  task report: :environment do
    buckets = { "<90d" => 90.days.ago..Time.current,
                "90d-1y" => 1.year.ago..90.days.ago,
                "1y-3y" => 3.years.ago..1.year.ago,
                ">3y" => Time.at(0)..3.years.ago }

    puts "[retention:report] paper_trail versions (per tenant)"
    Organization.pluck(:short_name).sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        counts = buckets.map { |label, range| "#{label}=#{PaperTrail::Version.where(created_at: range).count}" }
        puts "  tenant=#{tenant} #{counts.join(' ')}"
      end
    end

    puts "[retention:report] Mongo history stores (all tenants)"
    [ClientHistory, TaskHistory, AccessLog].each do |model|
      counts = buckets.map { |label, range| "#{label}=#{model.unscoped.where(:created_at.gte => range.begin, :created_at.lt => range.end).count}" }
      puts "  #{model.name} #{counts.join(' ')}"
    end
  end
end
