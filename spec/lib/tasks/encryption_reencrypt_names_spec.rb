# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# UX round 3 (C1) + the 2026-07-23 box re-run lesson. encryption:reencrypt_client_names
# migrates LEGACY rows (old-scheme ciphertext, NULL original_* sidecar) onto the ignore_case
# scheme, and MUST be idempotent BY SKIPPING: on an already-migrated row read_attribute(col)
# returns the DOWNCASED ignore_case column, and the task's original blind re-write pushed that
# into the display sidecar — lowercasing every client name on the pilot box the first time a
# deploy re-ran it. Runs the REAL task (test env has the single 'app' tenant).
RSpec.describe 'encryption:reencrypt_client_names' do
  before(:all) do
    Rake.application.rake_require('tasks/encryption', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) { ClientHistory.delete_all }
  after(:each)  { ClientHistory.delete_all; ENV.delete('CONFIRM') }

  def run_task
    ENV['CONFIRM'] = '1'
    Rake::Task['encryption:reencrypt_client_names'].reenable
    Rake::Task['encryption:reencrypt_client_names'].invoke
  end

  # A row the C1 migration hasn't reached: old-scheme (deterministic, no ignore_case)
  # ciphertext in the column, NULL sidecar. Same simulation as tier4_encryption_spec.
  def make_legacy!(client, col, value)
    old_type = Client.type_for_attribute(col).previous_types.first
    expect(old_type).to be_present, "expected a previous: scheme on #{col}"
    Client.connection.update(
      "UPDATE clients SET #{col} = #{Client.connection.quote(old_type.serialize(value))}, " \
      "original_#{col} = NULL WHERE id = #{client.id}"
    )
  end

  it 'migrates a legacy row, preserving the ORIGINAL case in the display sidecar' do
    client = create(:client, given_name: 'Placeholder')
    make_legacy!(client, :given_name, 'Solara')
    expect(Client.find(client.id).given_name).to be_nil # the pre-reencrypt window

    run_task

    migrated = Client.find(client.id)
    expect(migrated.given_name).to eq('Solara')
    expect(migrated.read_attribute(:original_given_name)).to eq('Solara')
    expect(Client.where(given_name: 'SOLARA')).to include(client) # case-insensitive now
  end

  it 'is idempotent: re-runs never lowercase migrated names (2026-07-23 box regression)' do
    client = create(:client, given_name: 'Yusuf', family_name: 'Hassan')

    run_task
    run_task

    survivor = Client.find(client.id)
    expect(survivor.given_name).to eq('Yusuf')
    expect(survivor.family_name).to eq('Hassan')
  end

  it 'refuses without CONFIRM=1' do
    ENV.delete('CONFIRM')
    Rake::Task['encryption:reencrypt_client_names'].reenable
    expect { Rake::Task['encryption:reencrypt_client_names'].invoke }.to raise_error(SystemExit)
  end
end
