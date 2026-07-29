# frozen_string_literal: true

# POAM-024 (PR A2) — backfill + verify for the Tier-5 search-entry sidecar
# (PropertiesSearchEntry subclasses, kept in lock-step by PropertiesSearchable's diff-sync).
#
# `backfill` walks every Tier-5 record in every tenant and calls THE SAME diff-sync the after_save
# callback uses — so it inserts only missing pairs and deletes only stale rows. A second consecutive
# run therefore reports added=0 removed=0 with ZERO writes (ids and updated_at byte-stable): that is
# the idempotence contract bootstrap.sh step 7d re-proves on EVERY deploy (the #203 standard —
# non-idempotent deploy-time rewrites are how the 2026-07-23 name-loss incident happened).
#
# `verify` recomputes the desired pair-set per record and non-zero-exits on ANY drift — the deploy
# gate (set -e in bootstrap halts on it). Output is VALUES-FREE: counts and ids only, never labels
# or values.
#
# The resume journal exists ONLY to resume a crashed WRITE run (batch-max-id per the #205 lesson);
# it is DELETED on successful completion so the next deploy re-walks everything — the walk IS the
# proof. O(n)-decrypt per deploy is deliberate and acceptable (deploy-time batch, not a request
# path); the request path is what POAM-024 fixes.
namespace :properties_search do
  PS_SIDECAR_MODELS = %w[CustomFieldProperty ClientEnrollment ClientEnrollmentTracking LeaveProgram].freeze
  PS_PROGRESS_PATH  = Rails.root.join('tmp', 'properties_search_backfill_progress.json')
  PS_BATCH_DEFAULT  = '500'

  def ps_tenants
    if (one = ENV['TENANT'].presence)
      [one]
    else
      Organization.pluck(:short_name).compact.sort
    end
  end

  def ps_load_progress
    return {} unless File.exist?(PS_PROGRESS_PATH)
    JSON.parse(File.read(PS_PROGRESS_PATH))
  rescue JSON::ParserError
    {}
  end

  def ps_save_progress(progress)
    FileUtils.mkdir_p(File.dirname(PS_PROGRESS_PATH))
    File.write(PS_PROGRESS_PATH, JSON.pretty_generate(progress))
  end

  desc 'Rebuild/diff-sync the Tier-5 search-entry sidecar across ALL tenants. ' \
       'DRY-RUN unless CONFIRM=1. TENANT= narrows, BATCH=500, RESET=1 clears the resume journal.'
  task backfill: :environment do
    # STRICT-MODE exception (mirrors encryption:backfill): reading .properties on a plaintext
    # straggler mid-window must not raise. Bootstrap runs encryption:backfill TIER=5 (7b) before
    # this (7d), so this is belt-and-braces for out-of-order manual runs; the sidecar VALUES we
    # write always go through the encrypted type regardless.
    ActiveRecord::Encryption.config.support_unencrypted_data = true

    confirm    = ENV['CONFIRM'] == '1'
    batch_size = Integer(ENV.fetch('BATCH', PS_BATCH_DEFAULT))
    tenants    = ps_tenants

    if ENV['RESET'] == '1'
      File.delete(PS_PROGRESS_PATH) if File.exist?(PS_PROGRESS_PATH)
      puts '[properties_search:backfill] resume journal RESET.'
    end
    progress = ps_load_progress

    puts "[properties_search:backfill] mode=#{confirm ? 'WRITE' : 'DRY-RUN'} batch=#{batch_size} " \
         "tenants=#{tenants.size} models=#{PS_SIDECAR_MODELS.join(',')}"
    grand = { records: 0, added: 0, removed: 0 }

    tenants.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        puts "\n== tenant=#{tenant} =="

        PS_SIDECAR_MODELS.each do |model_name|
          model = model_name.constantize
          key   = "#{tenant}|#{model_name}"
          # The journal only ever holds batch-max ids from a CRASHED confirm run — resume after
          # them. DRY-RUN never consults it (a dry-run must always report the full picture).
          resume_after = confirm ? progress.fetch(key, 0) : 0

          counts = { records: 0, added: 0, removed: 0 }
          model.where('id > ?', resume_after).find_in_batches(batch_size: batch_size) do |batch|
            batch.each do |record|
              delta = record.sync_properties_search_entries!(dry_run: !confirm)
              counts[:records] += 1
              counts[:added]   += delta[:added]
              counts[:removed] += delta[:removed]
            end
            if confirm
              # Journal the BATCH max id (the #205 lesson: never the last-iterated record —
              # an interleaved insert would rewind the resume point).
              progress[key] = batch.map(&:id).max
              ps_save_progress(progress)
            end
          end

          puts format('  %-26s records=%-6d added=%-6d removed=%-6d%s',
                      model_name, counts[:records], counts[:added], counts[:removed],
                      resume_after.positive? ? " (resumed after id #{resume_after})" : '')
          grand.merge!(counts) { |_k, a, b| a + b }
        end
      end
    end

    if confirm && File.exist?(PS_PROGRESS_PATH)
      # Completed run: the journal has done its job. Delete it so the NEXT deploy re-walks
      # everything and re-proves added=0 removed=0.
      File.delete(PS_PROGRESS_PATH)
    end

    puts "\n[properties_search:backfill] TOTAL records=#{grand[:records]} added=#{grand[:added]} " \
         "removed=#{grand[:removed]}#{confirm ? '' : ' (DRY-RUN, nothing written)'}"
    puts '[properties_search:backfill] second-run contract: an immediate re-run must report ' \
         'added=0 removed=0.'
  end

  desc 'Verify every Tier-5 record\'s sidecar entries match its decrypted properties. ' \
       'Non-zero exit on any drift (the bootstrap 7d deploy gate). TENANT= narrows.'
  task verify: :environment do
    tenants = ps_tenants
    total   = { records: 0, drifted: 0 }

    tenants.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        PS_SIDECAR_MODELS.each do |model_name|
          model       = model_name.constantize
          entry_class = model.properties_search_entry_class
          foreign_key = model.properties_search_entry_foreign_key
          drifted     = 0
          records     = 0

          model.find_each(batch_size: 1000) do |record|
            records += 1
            desired  = record.properties_search_desired_pairs
            existing = entry_class.where(foreign_key => record.id)
                                  .map { |e| [e.field_label, e.value] }
            # Size check catches duplicate rows the Set comparison would mask. VALUES-FREE output.
            next if existing.size == desired.size && existing.to_set == desired

            drifted += 1
            puts "  !! [#{tenant}] #{model_name}##{record.id}: sidecar drift " \
                 "(expected #{desired.size} entries, found #{existing.size})"
          end

          puts format('  %-26s [%s] records=%-6d drifted=%d', model_name, tenant, records, drifted)
          total[:records] += records
          total[:drifted] += drifted
        end
      end
    end

    if total[:drifted].positive?
      abort "[properties_search:verify] FAIL: #{total[:drifted]}/#{total[:records]} record(s) " \
            'have a drifted sidecar — run `rake properties_search:backfill CONFIRM=1` and re-verify.'
    end
    puts "[properties_search:verify] PASS: #{total[:records]} record(s), sidecar in lock-step."
  end
end
