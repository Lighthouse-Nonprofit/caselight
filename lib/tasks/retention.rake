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
# Policy: docs/compliance/policies/data-retention.md. AccessLog retention stays in audit.rake (AU-11),
# but audit:purge shares THIS file's archive-manifest gate (the helpers are file-global, like
# retention_days!).
#
# Safety posture (mirrors audit.rake / encryption.rake):
#  - DRY-RUN by default; deletes ONLY when CONFIRM=1.
#  - HARD FLOOR: DAYS < 365 is refused outright. Change audit is a SECURITY.md commitment; deleting
#    young versions would undermine AU-family evidence. The floor is code, not convention.
#  - POAM-015 (closed): purges are ARCHIVE-GATED. A CONFIRM=1 purge deletes ONLY rows covered by a
#    VERIFIED archive-manifest entry (retention:archive -> retention:verify_archive), and deletes at
#    the MANIFEST's cutoff — deleted ⊆ archived by construction (append-only stores freeze the
#    window). With the gate code-enforced, the purges are safe to schedule (config/schedule.rb).
#
# Archive layout (ARCHIVE_DIR, default tmp/archives — the box mounts a persisted volume at
# /app/archives): <store>/<tenant>/<cutoff>.jsonl.gz + manifest.json keyed "store|tenant|cutoff_iso"
# -> {file, sha256, rows, created_at, verified_at}. The WORM tier (S3 Object Lock / equivalent)
# remains the documented infra hand-off (audit-retention.md §3) — this gate proves a local,
# checksummed, verified copy exists before anything is deleted.

namespace :retention do
  RETENTION_FLOOR_DAYS = 365
  AUDIT_FLOOR_DAYS     = 90
  ARCHIVE_TENANT_ALL   = '(all)'

  def retention_days!(task)
    days = Integer(ENV.fetch("DAYS", RETENTION_FLOOR_DAYS.to_s))
    if days < RETENTION_FLOOR_DAYS
      abort "[#{task}] REFUSED: DAYS=#{days} is below the #{RETENTION_FLOOR_DAYS}-day retention floor " \
            "(change-audit evidence; see docs/compliance/policies/data-retention.md)."
    end
    days
  end

  # ---- archive manifest helpers (shared with audit.rake) -------------------------------------------

  def archive_dir
    ENV['ARCHIVE_DIR'].presence || Rails.root.join('tmp', 'archives').to_s
  end

  def archive_manifest_path
    File.join(archive_dir, 'manifest.json')
  end

  def load_archive_manifest
    return {} unless File.exist?(archive_manifest_path)
    JSON.parse(File.read(archive_manifest_path))
  rescue JSON::ParserError
    {}
  end

  def save_archive_manifest(manifest)
    FileUtils.mkdir_p(archive_dir)
    File.write(archive_manifest_path, JSON.pretty_generate(manifest))
  end

  def archive_key(store, tenant, cutoff)
    "#{store}|#{tenant}|#{cutoff.utc.iso8601}"
  end

  # Stream `each`-able rows to <store>/<tenant>/<cutoff>.jsonl.gz and record the manifest entry
  # (verified_at: nil until retention:verify_archive recounts + re-checksums it).
  def write_archive!(manifest, store:, tenant:, cutoff:, rows:)
    rel  = File.join(store, tenant, "#{cutoff.utc.strftime('%Y%m%dT%H%M%SZ')}.jsonl.gz")
    path = File.join(archive_dir, rel)
    FileUtils.mkdir_p(File.dirname(path))

    count = 0
    Zlib::GzipWriter.open(path) do |gz|
      rows.each do |row|
        gz.puts(row)
        count += 1
      end
    end

    manifest[archive_key(store, tenant, cutoff)] = {
      'file'        => rel,
      'sha256'      => Digest::SHA256.file(path).hexdigest,
      'rows'        => count,
      'created_at'  => Time.current.utc.iso8601,
      'verified_at' => nil
    }
    save_archive_manifest(manifest)
    count
  end

  # The POAM-015 gate: newest VERIFIED manifest entry for (store, tenant) at or older than the
  # requested cutoff. Returns [cutoff_time, entry] or aborts. Purges DELETE AT THIS CUTOFF, never
  # the requested one — deleted ⊆ archived by construction.
  def verified_archive_for!(task, store, tenant, requested_cutoff)
    manifest = load_archive_manifest
    verified = manifest.select do |key, entry|
      key.start_with?("#{store}|#{tenant}|") && entry['verified_at'].present?
    end
    if verified.empty?
      abort "[#{task}] REFUSED: no VERIFIED archive exists for #{store}/#{tenant} — run " \
            "`rake retention:archive` then `rake retention:verify_archive` first (POAM-015 gate)."
    end

    eligible = verified.filter_map do |key, entry|
      cutoff = Time.iso8601(key.split('|', 3).last)
      [cutoff, entry] if cutoff <= requested_cutoff
    end
    if eligible.empty?
      abort "[#{task}] REFUSED: every verified #{store}/#{tenant} archive window is NEWER than the " \
            "requested cutoff (#{requested_cutoff.utc.iso8601}) — archive at this window first."
    end
    eligible.max_by(&:first)
  end

  # Candidate count must not exceed what the verified archive captured — more candidates than
  # archived rows means the archive missed rows (clock skew / backdated writes): refuse.
  def assert_archive_covers!(task, store, tenant, entry, candidates)
    return if candidates <= entry['rows'].to_i
    abort "[#{task}] REFUSED: #{candidates} candidate row(s) exceed the #{entry['rows']} archived " \
          "for #{store}/#{tenant} — the verified archive does not cover the window; re-archive."
  end

  # ---- archive + verify ----------------------------------------------------------------------------

  desc "Archive purge-eligible rows to ARCHIVE_DIR as gzip JSONL + manifest. access_logs at " \
       "AUDIT_DAYS (default #{AUDIT_FLOOR_DAYS}); versions + client/task histories at DAYS " \
       "(default 1095, floor #{RETENTION_FLOOR_DAYS}). Idempotent per (store, tenant, cutoff)."
  task archive: :environment do
    audit_days = Integer(ENV.fetch('AUDIT_DAYS', AUDIT_FLOOR_DAYS.to_s))
    abort "[retention:archive] REFUSED: AUDIT_DAYS=#{audit_days} is below the #{AUDIT_FLOOR_DAYS}-day floor." if audit_days < AUDIT_FLOOR_DAYS
    record_days  = Integer(ENV.fetch('DAYS', '1095'))
    abort "[retention:archive] REFUSED: DAYS=#{record_days} is below the #{RETENTION_FLOOR_DAYS}-day floor." if record_days < RETENTION_FLOOR_DAYS

    audit_cutoff  = audit_days.days.ago
    record_cutoff = record_days.days.ago
    manifest      = load_archive_manifest
    puts "[retention:archive] dir=#{archive_dir} access_logs<#{audit_cutoff.utc.iso8601} " \
         "versions/histories<#{record_cutoff.utc.iso8601}"

    # AccessLog — cross-tenant single window, like audit:purge.
    scope = AccessLog.unscoped.where(:created_at.lt => audit_cutoff)
    if scope.count.zero?
      puts "  access_logs: 0 rows — no archive written"
    else
      rows = Enumerator.new { |y| scope.each { |doc| y << doc.as_document.to_json } }
      n = write_archive!(manifest, store: 'access_logs', tenant: ARCHIVE_TENANT_ALL, cutoff: audit_cutoff, rows: rows)
      puts "  access_logs: archived #{n} row(s)"
    end

    # paper_trail versions — per tenant.
    Organization.pluck(:short_name).sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        scope = PaperTrail::Version.where("created_at < ?", record_cutoff)
        if scope.count.zero?
          puts "  versions/#{tenant}: 0 rows — no archive written"
        else
          rows = Enumerator.new { |y| scope.find_each { |v| y << v.attributes.to_json } }
          n = write_archive!(manifest, store: 'versions', tenant: tenant, cutoff: record_cutoff, rows: rows)
          puts "  versions/#{tenant}: archived #{n} row(s)"
        end
      end
    end

    # Mongo histories — cross-tenant single window each, like the purge.
    { 'client_histories' => ClientHistory, 'task_histories' => TaskHistory }.each do |store, model|
      scope = model.unscoped.where(:created_at.lt => record_cutoff)
      if scope.count.zero?
        puts "  #{store}: 0 rows — no archive written"
      else
        rows = Enumerator.new { |y| scope.each { |doc| y << doc.as_document.to_json } }
        n = write_archive!(manifest, store: store, tenant: ARCHIVE_TENANT_ALL, cutoff: record_cutoff, rows: rows)
        puts "  #{store}: archived #{n} row(s)"
      end
    end

    puts "[retention:archive] DONE — manifest=#{archive_manifest_path} (run retention:verify_archive next)"
  end

  desc "Verify unverified archive-manifest entries (sha256 + row recount); stamp verified_at on " \
       "match. ALL=1 re-verifies everything. Exits 1 on any mismatch."
  task verify_archive: :environment do
    manifest = load_archive_manifest
    if manifest.empty?
      puts "[retention:verify_archive] nothing to verify (empty manifest at #{archive_manifest_path})"
      next
    end

    failures = 0
    manifest.each do |key, entry|
      next if entry['verified_at'].present? && ENV['ALL'] != '1'

      path = File.join(archive_dir, entry['file'].to_s)
      unless File.exist?(path)
        puts "  FAIL #{key}: file missing (#{entry['file']})"
        failures += 1
        next
      end

      sha   = Digest::SHA256.file(path).hexdigest
      count = Zlib::GzipReader.open(path) { |gz| gz.each_line.count }
      if sha == entry['sha256'] && count == entry['rows'].to_i
        entry['verified_at'] = Time.current.utc.iso8601
        puts "  OK   #{key} (#{count} row(s))"
      else
        puts "  FAIL #{key}: sha_match=#{sha == entry['sha256']} rows=#{count}/#{entry['rows']}"
        failures += 1
      end
    end
    save_archive_manifest(manifest)

    abort "[retention:verify_archive] FAIL — #{failures} entry(ies) did not verify" if failures.positive?
    puts "[retention:verify_archive] PASS — every archive entry is verified."
  end

  # ---- purges (archive-gated) ----------------------------------------------------------------------

  desc "Purge paper_trail versions older than DAYS (default/floor #{RETENTION_FLOOR_DAYS}) per tenant. " \
       "DRY-RUN unless CONFIRM=1; CONFIRM=1 deletes at the VERIFIED archive cutoff (POAM-015 gate). " \
       "Optional TENANT=short_name. e.g. DAYS=1095 CONFIRM=1 rake retention:purge_versions"
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

        archived_cutoff, entry = verified_archive_for!("retention:purge_versions", 'versions', tenant, cutoff)
        gated = PaperTrail::Version.where("created_at < ?", archived_cutoff)
        assert_archive_covers!("retention:purge_versions", 'versions', tenant, entry, gated.count)

        deleted = 0
        gated.in_batches(of: 1_000) { |batch| deleted += batch.delete_all }
        Rails.logger.info("[retention:purge_versions] tenant=#{tenant} DELETED #{deleted} versions (archived cutoff=#{archived_cutoff.iso8601})")
        puts "  tenant=#{tenant} DELETED=#{deleted} (verified-archive window #{archived_cutoff.utc.iso8601})"
      end
    end
    puts "  TOTAL candidates=#{grand_total}"
    puts "[retention:purge_versions] DRY-RUN — nothing deleted. CONFIRM=1 deletes rows covered by a verified archive (retention:archive + retention:verify_archive)." unless confirm
  end

  desc "Purge Mongo ClientHistory/TaskHistory older than DAYS (default/floor #{RETENTION_FLOOR_DAYS}) across ALL tenants " \
       "(shared Mongo, audit.rake idiom). DRY-RUN unless CONFIRM=1; CONFIRM=1 deletes at the VERIFIED archive cutoff."
  task purge_client_histories: :environment do
    days    = retention_days!("retention:purge_client_histories")
    confirm = ENV["CONFIRM"] == "1"
    cutoff  = days.days.ago

    puts "[retention:purge_client_histories] history docs older than #{days}d (created_at < #{cutoff.iso8601}) confirm=#{confirm}"
    { 'client_histories' => ClientHistory, 'task_histories' => TaskHistory }.each do |store, model|
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

      archived_cutoff, entry = verified_archive_for!("retention:purge_client_histories", store, ARCHIVE_TENANT_ALL, cutoff)
      gated = model.unscoped.where(:created_at.lt => archived_cutoff)
      assert_archive_covers!("retention:purge_client_histories", store, ARCHIVE_TENANT_ALL, entry, gated.count)

      deleted = gated.delete_all
      Rails.logger.info("[retention:purge_client_histories] #{model.name} DELETED #{deleted} docs (archived cutoff=#{archived_cutoff.iso8601})")
      puts "  #{model.name}: DELETED=#{deleted} (verified-archive window #{archived_cutoff.utc.iso8601})"
    end
    puts "[retention:purge_client_histories] DRY-RUN — nothing deleted. CONFIRM=1 deletes rows covered by a verified archive (retention:archive + retention:verify_archive)." unless confirm
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
