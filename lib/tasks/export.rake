# lib/tasks/export.rake
#
# POAM-014 — tenant-level full data export ("give the org their data back"; portability, SI-12).
# One tenant per run, operator-deliberate. NOT a backup (encrypted EBS snapshots are the backup
# control): this is the portable, per-org hand-off bundle.
#
# Bundle contents (tar.gz under tmp/exports/, optionally passphrase-encrypted):
#   pg/<tenant>.dump           pg_dump of the tenant's Apartment schema (custom format -Fc).
#                              The shared `public` schema (Organization row, shared config) is
#                              deliberately EXCLUDED — it is not the org's case data.
#   mongo/<collection>.jsonl.gz  ClientHistory / TaskHistory / AccessLog docs for this tenant.
#   uploads/...                Files referenced by THIS tenant's uploader-bearing rows. Upload
#                              dirs are NOT tenant-partitioned on disk, so selection is row-driven
#                              (walking the models inside the Apartment switch), never dir-driven.
#   manifest.json              sha256 + row/file counts per artifact.
#
# Every run writes a values-free `record_exported` AccessLog (privacy.rake precedent) — the export
# MUST NOT silently succeed unlogged. Optional EXPORT_PASSPHRASE encrypts the tarball with
# `openssl enc -aes-256-cbc -pbkdf2` (no new gems); the plaintext tar is removed.

namespace :export do
  # model => array-of-mount-names; walked INSIDE the tenant switch so ids resolve per-tenant.
  UPLOADER_MOUNTS = {
    'Attachment'             => %i[file image],
    'CustomFieldProperty'    => %i[attachments],
    'CaseNoteDomainGroup'    => %i[attachments],
    'FormBuilderAttachment'  => %i[file],
    'AssessmentDomain'       => %i[attachments]
  }.freeze

  MONGO_SLICES = { 'client_histories' => 'ClientHistory',
                   'task_histories'   => 'TaskHistory',
                   'access_logs'      => 'AccessLog' }.freeze

  def export_sha256(path)
    Digest::SHA256.file(path).hexdigest
  end

  def export_write_jsonl_gz(path, docs)
    FileUtils.mkdir_p(File.dirname(path))
    count = 0
    Zlib::GzipWriter.open(path) do |gz|
      docs.each do |doc|
        gz.puts(doc.as_document.to_json)
        count += 1
      end
    end
    count
  end

  desc 'Export ONE tenant (schema dump + Mongo slices + referenced uploads + manifest) to a ' \
       'tar.gz under tmp/exports/. TENANT= required; EXPORT_PASSPHRASE= encrypts the bundle. ' \
       'e.g. TENANT=cases rake export:tenant'
  task tenant: :environment do
    tenant = ENV['TENANT'].presence
    abort '[export:tenant] TENANT=<short_name> is required.' unless tenant
    org = Organization.find_by(short_name: tenant)
    abort "[export:tenant] unknown tenant #{tenant.inspect}." unless org

    ts     = Time.current.utc.strftime('%Y%m%dT%H%M%SZ')
    root   = Rails.root.join('tmp', 'exports')
    bundle = root.join("tenant_export_#{tenant}_#{ts}")
    FileUtils.mkdir_p(bundle)
    manifest = { 'tenant' => tenant, 'organization' => org.full_name,
                 'generated_at' => Time.current.utc.iso8601,
                 'contents' => 'tenant schema dump + tenant Mongo slices + row-referenced uploads; the shared public schema is excluded by design',
                 'artifacts' => {} }

    # 1. Postgres — the tenant's Apartment schema, custom format (pg_restore-able).
    config  = ActiveRecord::Base.connection_db_config.configuration_hash
    pg_path = bundle.join('pg', "#{tenant}.dump")
    FileUtils.mkdir_p(pg_path.dirname)
    env = { 'PGPASSWORD' => config[:password].to_s }
    cmd = ['pg_dump', '-Fc', '--no-acl', '--no-owner', '-n', tenant,
           '-h', config[:host].to_s, '-p', (config[:port] || 5432).to_s,
           '-U', config[:username].to_s, '-d', config[:database].to_s,
           '-f', pg_path.to_s]
    system(env, *cmd, exception: true)
    manifest['artifacts']["pg/#{tenant}.dump"] = { 'sha256' => export_sha256(pg_path), 'bytes' => File.size(pg_path) }
    puts "  pg: dumped schema #{tenant} (#{File.size(pg_path)} bytes)"

    # 2. Mongo slices — this tenant's docs only (unscoped + explicit tenant filter; the default
    #    scope is bound to Organization.current, which is unrelated in a rake context).
    MONGO_SLICES.each do |name, model_name|
      model = model_name.constantize
      docs  = model.unscoped.where(tenant: tenant)
      rel   = "mongo/#{name}.jsonl.gz"
      count = export_write_jsonl_gz(bundle.join(rel).to_s, docs)
      manifest['artifacts'][rel] = { 'sha256' => export_sha256(bundle.join(rel)), 'rows' => count }
      puts "  mongo: #{name} #{count} doc(s)"
    end

    # 3. Uploads — row-driven inside the tenant switch. CarrierWave uploaders expose #path (single
    #    mounts) or arrays of uploaders (mount_uploaders); copy preserving the public/uploads-relative
    #    layout so filenames keep their model/mount/id context.
    uploads_root = Rails.root.join('public', 'uploads').to_s
    files = 0
    Apartment::Tenant.switch(tenant) do
      UPLOADER_MOUNTS.each do |model_name, mounts|
        model = model_name.constantize
        model.find_each do |record|
          mounts.each do |mount|
            Array(record.public_send(mount)).each do |uploader|
              path = uploader.try(:path)
              next if path.blank? || !File.exist?(path)
              rel = path.sub("#{uploads_root}/", '')
              dest = bundle.join('uploads', rel)
              FileUtils.mkdir_p(dest.dirname)
              FileUtils.cp(path, dest)
              files += 1
            end
          end
        end
      end

      # 4. Values-free AU-2 evidence row, INSIDE the switch so the tenant field fills correctly.
      #    Direct create! (privacy.rake precedent) — the export must not silently succeed unlogged.
      AccessLog.create!(
        event_type: 'record_exported',
        resource_type: 'Organization',
        resource_id: org.id.to_s,
        metadata: { 'reason' => 'tenant_export', 'task' => 'export:tenant', 'source' => 'system' }
      )
    end
    manifest['artifacts']['uploads/'] = { 'files' => files }
    puts "  uploads: #{files} file(s)"

    File.write(bundle.join('manifest.json'), JSON.pretty_generate(manifest))

    # 5. Package (and optionally encrypt).
    tar_path = root.join("tenant_export_#{tenant}_#{ts}.tar.gz")
    system('tar', '-czf', tar_path.to_s, '-C', root.to_s, bundle.basename.to_s, exception: true)
    FileUtils.remove_entry(bundle)

    if ENV['EXPORT_PASSPHRASE'].present?
      enc_path = "#{tar_path}.enc"
      system({ 'EXPORT_PASSPHRASE' => ENV['EXPORT_PASSPHRASE'] },
             'openssl', 'enc', '-aes-256-cbc', '-pbkdf2', '-salt',
             '-in', tar_path.to_s, '-out', enc_path,
             '-pass', 'env:EXPORT_PASSPHRASE', exception: true)
      FileUtils.rm(tar_path)
      puts "[export:tenant] wrote #{enc_path} (aes-256-cbc; decrypt: openssl enc -d -aes-256-cbc -pbkdf2 -in <file> -out <tar.gz> -pass env:EXPORT_PASSPHRASE)"
    else
      puts "[export:tenant] wrote #{tar_path}"
      puts '[export:tenant] REMINDER: the bundle holds decrypted PII — hand off out-of-band, then delete it. Set EXPORT_PASSPHRASE= to encrypt.'
    end
  end
end
