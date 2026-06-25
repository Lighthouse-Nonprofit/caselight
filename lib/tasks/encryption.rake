# lib/tasks/encryption.rake
#
# Phase 4 (SC-28 / SOC 2 C1.1) — REUSABLE, per-tenant field-level-encryption tooling for ALL tiers.
#
#   bundle exec rake encryption:backfill                 # default TIER=1, all tenants, DRY-RUN
#   bundle exec rake encryption:backfill CONFIRM=1       # actually write ciphertext
#   bundle exec rake encryption:backfill TIER=1 CONFIRM=1 TENANT=app
#   bundle exec rake encryption:backfill MODELS=Client:reason_for_referral,background CONFIRM=1
#   bundle exec rake encryption:verify                   # gate before flipping support_unencrypted_data=false
#   BATCH=500 RESET=1 bundle exec rake encryption:backfill CONFIRM=1
#
# WHY A RAKE (not a migration): AR Encryption is WRITE-TIME. Declaring `encrypts :col` does NOT touch
# existing rows — they stay plaintext until re-saved. support_unencrypted_data=true
# (config/initializers/active_record_encryption.rb) lets reads tolerate that during the window. This
# task forces the write so every historical row becomes ciphertext, then `verify` proves it.
#
# MULTI-TENANCY (the crux): data lives in PER-TENANT Postgres SCHEMAS (Apartment, schema-per-tenant;
# only Organization is excluded/public — see config/initializers/apartment.rb). A rake process has no
# tenant switched, so we MUST iterate Organization.pluck(:short_name) and Apartment::Tenant.switch
# into each schema (block form auto-resets, even on exception — same idiom as
# lib/tasks/slo4home_taxonomy.rake and audit.rake). Models are NOT in the public schema, so only
# tenant schemas are processed.
#
# HOW WE FORCE ENCRYPTION (the load-bearing decision): we read each target attribute (AR decrypts it,
# or passes plaintext through under support_unencrypted_data=true) and write the SAME logical value
# back via `record.update_columns(col => value)`. In Rails 7.2 update_columns routes the write through
# the encrypted attribute TYPE's #serialize (=> ciphertext in Postgres) but structurally SKIPS:
#   * validations (historical rows that fail today's guards — e.g. a referred Client with a blank
#     rejected_note, or `validates :user_ids, presence: true` — must still get encrypted);
#   * ALL callbacks, critically Client `after_save :create_client_history` (which writes a
#     ClientHistory doc + embedded sub-docs to Mongo) and `after_update :reset_tasks_of_users` /
#     `:set_able_status` — re-saving every row would flood the AU-* audit/history store;
#   * paper_trail Versions (every model here is `has_paper_trail`); and the updated_at touch.
# We deliberately do NOT use `record.save!(validate: false)`: it fires those callbacks/paper_trail,
# and `save!` does NOT accept a `touch:` kwarg in Rails 7.2 (touch: is an update_columns/#touch arg),
# so any save!(..., touch: false) attempt would raise ArgumentError on the first row.
#
# IDEMPOTENT: re-running reads the decrypted value and writes the identical logical value back ->
# still valid ciphertext (non-deterministic => a fresh IV each write, but the same plaintext
# round-trips). Under support_unencrypted_data=true a half-migrated table reads cleanly throughout.
# RESUMABLE: progress (last processed id per tenant+model+column-signature) is journaled to
# tmp/encryption_backfill_progress.json after every batch; re-running resumes per key. RESET=1 clears it.

namespace :encryption do
  # ---- Registry: single source of truth for what each tier encrypts. ------------------------------
  # Later tiers ADD one entry here; the backfill/verify logic never changes. Each value is a
  # model-name => array of (already `encrypts`-declared) column symbols.
  ENCRYPTION_TIERS = {
    '1' => {
      'Client'       => %i[reason_for_referral background exit_note rejected_note
                           relevant_referral_information],
      'Family'       => %i[caregiver_information case_history],
      'ProgressNote' => %i[response additional_note]
    }
    # '2' => { 'Client' => %i[given_name family_name ...], 'User' => %i[email] }  # future tiers append here
  }.freeze

  PROGRESS_PATH = Rails.root.join('tmp', 'encryption_backfill_progress.json')
  BATCH_SIZE_DEFAULT = '500'
  VERIFY_BATCH = 1000

  # ---- shared helpers ----------------------------------------------------------------------------

  # Resolve the {ModelName => [cols]} map from MODELS= (explicit) or TIER= (registry).
  # MODELS format: "Client:col_a,col_b;Family:col_c"  (semicolon between models).
  def encryption_target_map
    if (raw = ENV['MODELS'].presence)
      raw.split(';').each_with_object({}) do |chunk, acc|
        model_name, cols = chunk.split(':', 2)
        acc[model_name.strip] = cols.to_s.split(',').map { |c| c.strip.to_sym }
      end
    else
      tier = ENV.fetch('TIER', '1')
      ENCRYPTION_TIERS.fetch(tier) do
        abort "[encryption] unknown TIER=#{tier.inspect}; known: #{ENCRYPTION_TIERS.keys.join(', ')}"
      end
    end
  end

  # Tenant schemas to walk. Organization is the excluded/public tenant holding the registry, so we
  # enumerate its short_names (matches config.tenant_names). TENANT= narrows to one (retry/CI).
  def encryption_tenants
    if (one = ENV['TENANT'].presence)
      [one]
    else
      Organization.pluck(:short_name).compact.sort
    end
  end

  # Stable signature for a model's target column set, so a resume entry only matches the SAME columns
  # (a later tier adding columns won't be wrongly skipped by an older journal entry).
  def column_signature(columns)
    columns.map(&:to_s).sort.join(',')
  end

  def progress_key(tenant, model_name, columns)
    "#{tenant}|#{model_name}|#{column_signature(columns)}"
  end

  def load_progress
    return {} unless File.exist?(PROGRESS_PATH)
    JSON.parse(File.read(PROGRESS_PATH))
  rescue JSON::ParserError
    {}
  end

  def save_progress(progress)
    FileUtils.mkdir_p(File.dirname(PROGRESS_PATH))
    File.write(PROGRESS_PATH, JSON.pretty_generate(progress))
  end

  # A raw stored value is ciphertext IFF it parses as an AR-Encryption MESSAGE ENVELOPE. We do NOT use
  # type#deserialize: under support_unencrypted_data=true (our migration window) deserialize TOLERATES
  # plaintext (returns it without raising), so it cannot tell ciphertext from a plaintext straggler —
  # which would make this gate falsely PASS on un-backfilled rows. message_serializer parses the
  # envelope structure (the {"p":..,"h":..} payload) WITHOUT needing the key, so detection is
  # key-independent AND tier-agnostic: deterministic and non-deterministic columns share the envelope
  # format, so later tiers reuse this unchanged. blank/NULL = nothing sensitive stored => not a straggler.
  def ciphertext?(_model, _attr, raw)
    return true if raw.nil? || raw == ''
    ActiveRecord::Encryption.message_serializer.load(raw)
    true
  rescue ActiveRecord::Encryption::Errors::Encoding, ActiveRecord::Encryption::Errors::ForbiddenClass
    false
  end

  # Read the decrypted/plaintext-passthrough attrs, then write them straight back through the
  # encrypted type via update_columns => ciphertext, no validations, no callbacks, no paper_trail,
  # no touch. Returns true if a write was issued.
  def encrypt_record!(record, columns, confirm)
    attrs = columns.each_with_object({}) { |c, h| h[c] = record.public_send(c) }
    record.update_columns(attrs) if confirm
    true
  end

  # ---- backfill ----------------------------------------------------------------------------------
  desc 'Encrypt-at-rest backfill across ALL tenants. DRY-RUN unless CONFIRM=1. ' \
       'TIER=1 (default) or MODELS="Model:col,col;..."; TENANT=, BATCH=500, RESET=1.'
  task backfill: :environment do
    target_map = encryption_target_map
    confirm    = ENV['CONFIRM'] == '1'
    batch_size = Integer(ENV.fetch('BATCH', BATCH_SIZE_DEFAULT))
    tenants    = encryption_tenants
    abort '[encryption:backfill] no targets resolved' if target_map.empty?

    if ENV['RESET'] == '1'
      File.delete(PROGRESS_PATH) if File.exist?(PROGRESS_PATH)
      puts '[encryption:backfill] progress journal RESET.'
    end
    progress = load_progress

    puts "[encryption:backfill] mode=#{confirm ? 'WRITE' : 'DRY-RUN'} batch=#{batch_size} " \
         "tenants=#{tenants.size} models=#{target_map.keys.join(',')}"
    grand = Hash.new(0)

    tenants.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        puts "\n== tenant=#{tenant} =="

        target_map.each do |model_name, columns|
          model = model_name.constantize

          # Guard: every target column MUST be `encrypts`-declared, else update_columns would write
          # PLAINTEXT and verify would (correctly) fail later. Fail loud, early.
          declared = model.respond_to?(:encrypted_attributes) ? model.encrypted_attributes.to_a : []
          missing  = columns.reject { |c| declared.include?(c) }
          unless missing.empty?
            abort "[encryption:backfill] #{model_name} is missing `encrypts` for: " \
                  "#{missing.join(', ')} — add the declarations before backfilling."
          end

          key       = progress_key(tenant, model_name, columns)
          resume_id = (progress[key] || 0).to_i
          processed = 0

          # Resume floor via the PK; let in_batches own ordering + cursor (it always orders by PK
          # ascending — do NOT add an explicit .order, which it warns about and overrides).
          relation = model.unscoped.where("#{model.quoted_primary_key} > ?", resume_id)

          relation.in_batches(of: batch_size) do |batch|
            max_id = nil
            batch.each do |record|
              max_id = record.id
              encrypt_record!(record, columns, confirm)
              processed += 1
            end
            if confirm && max_id
              progress[key] = max_id
              save_progress(progress)
            end
            print "  #{model_name}: #{processed} rows...\r"
          end

          grand[model_name] += processed
          verb = confirm ? 'encrypted' : 'would encrypt'
          puts "  #{model_name}: #{verb} #{processed} row(s) [cols: #{columns.join(', ')}]" \
               "#{resume_id.positive? ? " (resumed from id>#{resume_id})" : ''}"
          Rails.logger.info("[encryption:backfill] tenant=#{tenant} model=#{model_name} " \
                            "#{verb}=#{processed} cols=#{columns.join(',')}")
        end
      end
    end

    puts "\n[encryption:backfill] #{confirm ? 'DONE' : 'DRY-RUN'}"
    grand.each { |m, n| puts "  TOTAL #{m}: #{confirm ? 'encrypted' : 'would encrypt'}=#{n}" }
    unless confirm
      puts '[encryption:backfill] DRY-RUN only. Re-run with CONFIRM=1 to write ciphertext, ' \
           'then run `rake encryption:verify`.'
    end
  end

  # ---- verify ------------------------------------------------------------------------------------
  desc 'Verify every target column is ciphertext (no plaintext stragglers) across ALL tenants. ' \
       'Non-zero exit on stragglers. Gate before support_unencrypted_data=false. TIER=/MODELS=/TENANT=.'
  task verify: :environment do
    target_map = encryption_target_map
    tenants    = encryption_tenants
    abort '[encryption:verify] no targets resolved' if target_map.empty?

    puts "[encryption:verify] tenants=#{tenants.size} models=#{target_map.keys.join(',')}"
    stragglers = [] # [tenant, model, attr, id]

    tenants.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        target_map.each do |model_name, columns|
          model = model_name.constantize
          conn  = model.connection
          table = conn.quote_table_name(model.table_name)
          pk    = conn.quote_column_name(model.primary_key)

          columns.each do |attr|
            qcol    = conn.quote_column_name(attr)
            checked = 0
            bad     = 0
            last_id = 0
            # Batch the RAW read by PK so verify streams rather than loading the whole column into
            # memory (matters once a later tier targets a high-volume table). We read the RAW stored
            # bytes (bypassing the decrypting accessor) and round-trip each through the encrypted type.
            loop do
              rows = conn.select_rows(
                "SELECT #{pk}, #{qcol} FROM #{table} WHERE #{pk} > #{conn.quote(last_id)} " \
                "ORDER BY #{pk} ASC LIMIT #{VERIFY_BATCH}"
              )
              break if rows.empty?
              rows.each do |id, raw|
                last_id = id
                checked += 1
                next if ciphertext?(model, attr, raw)
                bad += 1
                stragglers << [tenant, model_name, attr, id]
              end
              break if rows.size < VERIFY_BATCH
            end
            status = bad.zero? ? 'OK  ' : 'FAIL'
            puts "  #{status} #{tenant}/#{model_name}.#{attr} (#{checked} row(s)" \
                 "#{bad.zero? ? '' : ", #{bad} straggler(s)"})"
          end
          Rails.logger.info("[encryption:verify] tenant=#{tenant} model=#{model_name} " \
                            "checked cols=#{columns.join(',')}")
        end
      end
    end

    if stragglers.empty?
      puts "\n[encryption:verify] PASS — every target column is ciphertext in every tenant. " \
           'Safe to plan the support_unencrypted_data=false cutover.'
    else
      puts "\n[encryption:verify] FAIL — #{stragglers.size} plaintext straggler(s):"
      stragglers.first(50).each { |t, m, a, id| puts "  tenant=#{t} #{m}##{id}.#{a}" }
      puts "  ...(+#{stragglers.size - 50} more)" if stragglers.size > 50
      abort '[encryption:verify] stragglers present — run encryption:backfill CONFIRM=1; do NOT flip strict mode.'
    end
  end
end