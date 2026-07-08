# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 6 (U9) — subject-access export. Contract: refuses without TENANT/CLIENT; the JSON contains
# the subject's records (and only that client's), never staff PII columns; a values-free
# record_exported AccessLog row is written; output lands under tmp/exports.
RSpec.describe 'privacy:subject_access_export' do
  before(:all) do
    Rake.application.rake_require('tasks/privacy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    AccessLog.unscoped.delete_all rescue nil
    ClientHistory.unscoped.delete_all rescue nil
    FileUtils.rm_rf(Rails.root.join('tmp', 'exports'))
  end

  after(:each) do
    AccessLog.unscoped.delete_all rescue nil
    ClientHistory.unscoped.delete_all rescue nil
    FileUtils.rm_rf(Rails.root.join('tmp', 'exports'))
    ENV.delete('TENANT'); ENV.delete('CLIENT')
  end

  def run_task
    Rake::Task['privacy:subject_access_export'].reenable
    Rake::Task['privacy:subject_access_export'].invoke
  end

  it 'refuses to run without TENANT and CLIENT' do
    expect { run_task }.to raise_error(SystemExit)
  end

  it 'exports the client subject data, logs it, and excludes staff PII' do
    tenant = Apartment::Tenant.current
    allow(Organization).to receive(:exists?).with(short_name: tenant).and_return(true)
    allow(Apartment::Tenant).to receive(:switch).with(tenant).and_yield

    staff  = create(:user, roles: 'case worker', first_name: 'StaffExportSecret')
    client = create(:client, given_name: 'SubjectGiven', current_address: 'SUBJECT_ADDR', users: [staff])
    other  = create(:client, given_name: 'OtherClientSecret')

    cf = create(:custom_field, entity_type: 'Client', form_title: 'Export Form',
                fields: [{ 'type' => 'text', 'label' => 'Answer' }])
    create(:custom_field_property, custom_field: cf, custom_formable: client,
           properties: { 'Answer' => 'SUBJECT_FORM_VALUE' })

    ENV['TENANT'] = tenant
    ENV['CLIENT'] = client.id.to_s
    expect { run_task }.to output(/wrote .*subject_access_/).to_stdout

    file = Dir[Rails.root.join('tmp', 'exports', '*.json').to_s].sole
    json = JSON.parse(File.read(file))

    expect(json['client']['given_name']).to eq('SubjectGiven')
    expect(json['client']['current_address']).to eq('SUBJECT_ADDR')
    expect(json['custom_forms'].first['properties']).to eq('Answer' => 'SUBJECT_FORM_VALUE')

    raw = File.read(file)
    expect(raw).not_to include('OtherClientSecret')   # only THIS subject's records
    expect(raw).not_to include('StaffExportSecret')   # no staff PII
    expect(raw).not_to include('encrypted_password')

    log = AccessLog.unscoped.where(event_type: 'record_exported').last
    expect(log).to be_present
    expect(log.resource_type).to eq('Client')
    expect(log.resource_id).to eq(client.id.to_s)
    expect(log.metadata['reason']).to eq('subject_access_request')
  end
end
