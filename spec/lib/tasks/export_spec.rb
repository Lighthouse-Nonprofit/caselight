# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# POAM-014 — export:tenant, the per-org portability bundle. Invokes the REAL rake task: the crux
# is the end-to-end packaging (pg_dump of the tenant schema, tenant-filtered Mongo slices,
# row-driven upload selection, manifest, tar.gz, optional passphrase encryption) and the mandatory
# record_exported AccessLog.
RSpec.describe 'export:tenant rake task' do
  before(:all) do
    Rake.application.rake_require('tasks/export', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
    FileUtils.rm_rf(Rails.root.join('tmp', 'exports'))
  end

  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
    FileUtils.rm_rf(Rails.root.join('tmp', 'exports'))
    ENV.delete('TENANT'); ENV.delete('EXPORT_PASSPHRASE')
  end

  def run_task
    Rake::Task['export:tenant'].reenable
    Rake::Task['export:tenant'].invoke
  end

  def tenant
    Apartment::Tenant.current
  end

  def export_tarball
    Dir[Rails.root.join('tmp', 'exports', 'tenant_export_*.tar.gz').to_s].first
  end

  def extract!(tar_path)
    dir = Dir.mktmpdir('export-spec')
    system('tar', '-xzf', tar_path, '-C', dir, exception: true)
    Dir[File.join(dir, 'tenant_export_*')].first
  end

  it 'aborts without TENANT= and on an unknown tenant' do
    expect { run_task }.to raise_error(SystemExit)
    ENV['TENANT'] = 'no-such-tenant'
    expect { run_task }.to raise_error(SystemExit)
    expect(export_tarball).to be_nil
  end

  it 'bundles the schema dump, tenant Mongo slices, referenced uploads and a manifest — and logs the export' do
    client = create(:client) # writes a ClientHistory doc for this tenant
    cf  = create(:custom_field, entity_type: 'Client', form_title: 'Export Docs',
                 fields: [{ 'type' => 'file', 'label' => 'Doc', 'name' => 'file-1' }])
    cfp = create(:custom_field_property, custom_field: cf, custom_formable: client,
                 attachments: [Rack::Test::UploadedFile.new(
                   Rails.root.join('spec/supports/download_fixture.pdf').to_s, 'application/pdf'
                 )])

    ENV['TENANT'] = tenant
    expect { run_task }.to output(/wrote .*tenant_export_#{tenant}/).to_stdout

    tar = export_tarball
    expect(tar).to be_present
    bundle = extract!(tar)

    manifest = JSON.parse(File.read(File.join(bundle, 'manifest.json')))
    expect(manifest['tenant']).to eq(tenant)
    expect(manifest['artifacts']["pg/#{tenant}.dump"]['bytes']).to be > 0
    expect(manifest['artifacts']['mongo/client_histories.jsonl.gz']['rows']).to be >= 1
    expect(manifest['artifacts']['uploads/']['files']).to be >= 1

    # The pg dump is a real custom-format archive ("PGDMP" magic), scoped to the tenant schema.
    dump = File.join(bundle, 'pg', "#{tenant}.dump")
    expect(File.binread(dump, 5)).to start_with('PGDMP')

    # The referenced upload rode along with its public/uploads-relative layout.
    copied = Dir[File.join(bundle, 'uploads', '**', '*')].select { |f| File.file?(f) }
    expect(copied.map { |f| File.basename(f) }).to include(File.basename(Array(cfp.attachments).first.path))

    # The Mongo slice holds THIS tenant's history doc(s).
    gz = File.join(bundle, 'mongo', 'client_histories.jsonl.gz')
    lines = Zlib::GzipReader.open(gz) { |z| z.each_line.to_a }
    expect(lines.size).to eq(manifest['artifacts']['mongo/client_histories.jsonl.gz']['rows'])

    # Mandatory values-free audit row, written inside the tenant switch.
    log = AccessLog.unscoped.where(event_type: 'record_exported').last
    expect(log).to be_present
    expect(log.metadata['reason']).to eq('tenant_export')
    expect(log.tenant).to eq(tenant)
  end

  it 'encrypts the bundle when EXPORT_PASSPHRASE is set (and the plaintext tar is gone)' do
    create(:client)
    ENV['TENANT'] = tenant
    ENV['EXPORT_PASSPHRASE'] = 'spec-passphrase-42'
    expect { run_task }.to output(/aes-256-cbc/).to_stdout

    enc = Dir[Rails.root.join('tmp', 'exports', '*.tar.gz.enc').to_s].first
    expect(enc).to be_present
    expect(export_tarball).to be_nil # plaintext removed

    # Round-trip: openssl decrypts back to a valid gzip (magic bytes 1f 8b).
    out = "#{enc}.roundtrip.tar.gz"
    system({ 'EXPORT_PASSPHRASE' => 'spec-passphrase-42' },
           'openssl', 'enc', '-d', '-aes-256-cbc', '-pbkdf2',
           '-in', enc, '-out', out, '-pass', 'env:EXPORT_PASSPHRASE', exception: true)
    expect(File.binread(out, 2).bytes).to eq([0x1f, 0x8b])
  end
end
