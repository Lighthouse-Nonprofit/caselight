# lib/tasks/history_redaction.rake
#
# Phase 6 (U4) — the ONE-TIME scrub that finishes POAM-SC28-HIST. U2 (paper_trail skip:) and U3
# (HistoryPiiFilter) stop NEW plaintext PII from entering the history stores; rows written before
# they merged still carry decrypted copies of the Phase-4-encrypted columns. These tasks redact
# those rows IN PLACE (who/when/event metadata and every non-PII key survive) and verify zero
# stragglers remain — the same backfill-then-verify shape as encryption.rake.
#
# Sources of truth (NOT hand-copied lists):
#   * versions  -> each model's has_paper_trail skip: list (paper_trail_options[:skip], U2)
#   * Mongo     -> Model.encrypted_attributes + HistoryPiiFilter::EXTRA_DENYLIST (U3)
# so a future addition to either automatically widens the scrub.
#
# Safety posture (mirrors audit.rake / retention.rake): DRY-RUN unless CONFIRM=1; idempotent
# (re-run touches nothing once clean); update_columns (no callbacks, no touch, no new versions);
# per-tenant iteration for Postgres, cross-tenant unscoped for the shared Mongo db.
#
# Serialization: this app's version payloads are YAML (probed on live rows). Rows are parsed with
# the SafeVersionValue ladder (JSON-then-YAML, the app's single tolerant parser) and re-serialized
# in the SAME format detected on read, so SensitiveVersionScope / Version#changeset behavior is
# unchanged. Unparseable rows are REPORTED, never guessed at — they are the operator's
# purge-fallback set (delete via retention:purge_versions or by id).

namespace :history do
  def redacted_models
    Rails.application.eager_load!
    ActiveRecord::Base.descendants.select do |klass|
      klass.respond_to?(:paper_trail_options) &&
        klass.paper_trail_options.is_a?(Hash) &&
        Array(klass.paper_trail_options[:skip]).any?
    end
  end

  def parse_payload(raw)
    return [nil, nil] if raw.blank?
    format = raw.lstrip.start_with?('{') ? :json : :yaml
    parsed = SafeVersionValue.parse(raw)
    [parsed.is_a?(Hash) ? parsed : nil, format]
  end

  def dump_payload(hash, format)
    format == :json ? JSON.generate(hash) : YAML.dump(hash)
  end

  desc "Redact skip-listed PII keys from EXISTING paper_trail versions (per tenant). " \
       "DRY-RUN unless CONFIRM=1. Optional TENANT=short_name."
  task scrub_versions: :environment do
    confirm = ENV["CONFIRM"] == "1"
    tenants = Organization.pluck(:short_name)
    tenants &= [ENV["TENANT"]] if ENV["TENANT"].present?
    abort "[history:scrub_versions] no matching tenant" if tenants.empty?

    skip_map = redacted_models.to_h { |k| [k.name, Array(k.paper_trail_options[:skip]).map(&:to_s)] }
    puts "[history:scrub_versions] models: #{skip_map.keys.sort.join(', ')} confirm=#{confirm}"

    tenants.sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        dirty = 0
        unparseable = []
        skip_map.each do |item_type, keys|
          PaperTrail::Version.where(item_type: item_type).find_each(batch_size: 500) do |version|
            updates = {}
            %i[object object_changes].each do |col|
              raw = version.read_attribute_before_type_cast(col).to_s
              next if raw.blank?
              hash, format = parse_payload(raw)
              if hash.nil?
                unparseable << "#{item_type}##{version.id}.#{col}"
                next
              end
              next unless (hash.keys.map(&:to_s) & keys).any?
              updates[col] = dump_payload(hash.except(*keys, *keys.map(&:to_sym)), format)
            end
            next if updates.empty?
            dirty += 1
            version.update_columns(updates) if confirm
          end
        end
        puts "  tenant=#{tenant} #{confirm ? 'REDACTED' : 'candidates'}=#{dirty}" \
             "#{unparseable.any? ? " UNPARSEABLE=#{unparseable.size} (#{unparseable.first(5).join(', ')}…)" : ''}"
      end
    end
    puts "[history:scrub_versions] DRY-RUN — nothing written. Re-run with CONFIRM=1." unless confirm
  end

  desc "Verify NO paper_trail version still carries a skip-listed PII key (per tenant). Exits 1 on failure."
  task verify_versions: :environment do
    skip_map = redacted_models.to_h { |k| [k.name, Array(k.paper_trail_options[:skip]).map(&:to_s)] }
    failures = 0
    Organization.pluck(:short_name).sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        bad = 0
        skip_map.each do |item_type, keys|
          PaperTrail::Version.where(item_type: item_type).find_each(batch_size: 500) do |version|
            %i[object object_changes].each do |col|
              hash, _fmt = parse_payload(version.read_attribute_before_type_cast(col).to_s)
              next if hash.nil?
              bad += 1 if (hash.keys.map(&:to_s) & keys).any?
            end
          end
        end
        failures += bad
        puts "  tenant=#{tenant} #{bad.zero? ? 'PASS' : "FAIL rows=#{bad}"}"
      end
    end
    abort "[history:verify_versions] FAIL — #{failures} version payload(s) still carry PII keys" if failures.positive?
    puts "[history:verify_versions] PASS — no skip-listed keys remain."
  end

  # Dotted $unset paths for the Mongo scrub, derived from the SAME denylists HistoryPiiFilter uses.
  def mongo_unset_map
    user_keys   = HistoryPiiFilter.scrub_keys_for(User)
    client_keys = HistoryPiiFilter.scrub_keys_for(Client)
    family_keys = HistoryPiiFilter.scrub_keys_for(Family)
    case_keys   = HistoryPiiFilter.scrub_keys_for(Case)
    cfp_keys    = HistoryPiiFilter.scrub_keys_for(CustomFieldProperty)

    {
      ClientHistory => client_keys.map { |k| "object.#{k}" } +
                       user_keys.map   { |k| "case_worker_client_histories.$[].object.#{k}" } +
                       family_keys.map { |k| "client_family_histories.$[].object.#{k}" } +
                       case_keys.map   { |k| "case_client_histories.$[].object.#{k}" } +
                       cfp_keys.map    { |k| "client_custom_field_property_histories.$[].object.#{k}" },
      TaskHistory   => user_keys.map { |k| "case_worker_task_histories.$[].object.#{k}" }
    }
  end

  desc "Redact PII keys from EXISTING Mongo ClientHistory/TaskHistory docs (all tenants, shared db). " \
       "DRY-RUN unless CONFIRM=1."
  task scrub_client_histories: :environment do
    confirm = ENV["CONFIRM"] == "1"
    mongo_unset_map.each do |model, paths|
      # The all-positional $[] operator ERRORS on documents where the embedded array is absent, so
      # group the paths by array prefix and run one filtered update_many per group ('<array>.0'
      # exists => the array is present AND non-empty). Top-level unsets are safe unconditionally
      # (unsetting an absent path is a no-op). All idempotent.
      groups = paths.group_by { |p| p.include?('$[]') ? p.split('.$[]').first : nil }
      top_level = groups.delete(nil) || []

      candidates = top_level.any? ? model.unscoped.where('$or' => top_level.map { |p| { p => { '$exists' => true } } }).count : 0
      puts "[history:scrub_client_histories] #{model.name}: top-level candidates=#{candidates} paths=#{paths.size} confirm=#{confirm}"
      next unless confirm

      if top_level.any?
        result = model.collection.update_many({}, { '$unset' => top_level.to_h { |p| [p, ''] } })
        puts "  #{model.name} top-level: matched=#{result.matched_count} modified=#{result.modified_count}"
      end
      groups.each do |array_prefix, group_paths|
        result = model.collection.update_many(
          { "#{array_prefix}.0" => { '$exists' => true } },
          { '$unset' => group_paths.to_h { |p| [p, ''] } }
        )
        puts "  #{model.name} #{array_prefix}: matched=#{result.matched_count} modified=#{result.modified_count}"
      end
    end
    puts "[history:scrub_client_histories] DRY-RUN — nothing written. Re-run with CONFIRM=1." unless confirm
  end

  desc "Verify NO Mongo history doc still carries a redacted PII path. Exits 1 on failure."
  task verify_client_histories: :environment do
    failures = 0
    mongo_unset_map.each do |model, paths|
      bad = paths.sum do |p|
        # $exists works through arrays with plain dotted paths (drop the positional marker).
        model.unscoped.where(p.sub('.$[]', '') => { '$exists' => true }).count
      end
      failures += bad
      puts "  #{model.name}: #{bad.zero? ? 'PASS' : "FAIL paths_present=#{bad}"}"
    end
    abort "[history:verify_client_histories] FAIL — #{failures} PII path(s) still present" if failures.positive?
    puts "[history:verify_client_histories] PASS — no redacted paths remain."
  end
end
