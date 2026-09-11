# frozen_string_literal: true

require 'rails_helper'
require 'rake'
require 'json'
require 'tempfile'

# SLO for HOME intake import (slo4home:import_intake).
#
# The behaviour worth pinning is the SAFETY RAIL, not the happy path: this task carries CMIA
# "medical information" (physical and mental health needs recorded in the org's intake workbook)
# and routes it ONLY to custom forms whose sensitivity is `emergency_only`. If a form's
# sensitivity is ever loosened — by a reseed, a classify pass, or someone editing the taxonomy —
# the import must ABORT rather than quietly write medical records onto a surface every staff
# member can read. That failure would be silent and irreversible in the worst way: the data is
# already out before anyone notices.
RSpec.describe 'slo4home:import_intake' do
  before(:all) do
    Rake.application.rake_require('tasks/slo4home_import', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  let(:task) { Rake::Task['slo4home:import_intake'] }
  let(:tenant) { Apartment::Tenant.current }

  # Minimal one-person household carrying BOTH health columns.
  let(:payload) do
    { 'source' => 'spec fixture', 'parsed_at' => '2026-09-11T00:00:00',
      'households' => [
        { 'label' => 'Family 1', 'source_row' => 2, 'prospective' => false,
          'household' => { 'address' => '1 Spec St', 'support_status' => 'Active' },
          'members' => [
            { 'source_row' => 3, 'given_name' => 'Specperson', 'family_name' => '',
              'person' => { 'language' => 'Dari',
                            'physical_health_needs' => 'spec physical',
                            'mental_health_needs' => 'spec mental' },
              'overrides' => {} }
          ] }
      ], 'anomalies' => [] }
  end

  def write_payload
    f = Tempfile.new(['slo_import', '.json'])
    f.write(JSON.generate(payload))
    f.flush
    f
  end

  def run_task(env)
    task.reenable
    env.each { |k, v| ENV[k] = v.to_s }
    task.invoke
  ensure
    env.each_key { |k| ENV.delete(k) }
  end

  before do
    # The taxonomy the task requires. Seeded directly rather than by invoking the seed task so the
    # spec pins THIS task's contract, not the seed's.
    mk = ->(label) { { 'name' => label, 'label' => label, 'type' => 'text' } }
    form = lambda do |entity, title, labels, sensitivity = nil|
      attrs = { entity_type: entity, form_title: title, ngo_name: 'Spec',
                fields: labels.map { |l| mk.call(l) } }
      attrs[:sensitivity] = sensitivity if sensitivity
      CustomField.create!(**attrs)
    end

    form.call('Family', 'Family Summary',
              ['Primary Phone', 'Mailing Address', 'Contact Preference (call or text)', 'Support Status'])
    form.call('Family', 'Housing', ['Last Rental Support Month'])
    form.call('Family', 'Immigration', ['Arrival Date in the US'])
    form.call('Client', 'Member: Language & Communication', ['Primary Language'])
    form.call('Client', 'Adult: Employment',
              ['Current Employment', 'Individual Assessment and Plan', 'Community Employment Supports',
               'Profession (pre-arrival)', 'Employable?', 'Employment Barriers', 'First Job in the US',
               'Volunteer Work'])
    form.call('Client', 'Adult: Education', ['Education Background (pre-arrival)', 'Vocational Training'])
    form.call('Client', 'Confidential Health Information',
              ['Category', 'Recorded On', 'Confidential Notes'], 'emergency_only')
    form.call('Client', 'Member: Mental Health (EMERGENCIES ONLY)',
              ['Mental Health Needs'], 'emergency_only')
    create(:user) # satisfies Client's user_ids presence requirement via ACTIVE_STAFF fallback
  end

  describe 'the CMIA routing guard' do
    it 'ABORTS rather than writing health data to a form that is not emergency_only' do
      CustomField.find_by(entity_type: 'Client', form_title: 'Confidential Health Information')
                 .update!(sensitivity: 'standard')
      f = write_payload

      expect { run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1') }
        .to raise_error(SystemExit)

      expect(Client.where(code: 'SLO-FAMILY1-SPECPERSON')).to be_empty
    end

    it 'proceeds when both health forms are emergency_only' do
      f = write_payload
      expect { run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1') }
        .not_to raise_error
      expect(Client.find_by(code: 'SLO-FAMILY1-SPECPERSON')).to be_present
    end

    it 'aborts when a required form is missing entirely (never invents one)' do
      CustomField.find_by(entity_type: 'Client', form_title: 'Adult: Employment').destroy
      f = write_payload

      expect { run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1') }
        .to raise_error(SystemExit)
    end
  end

  describe 'write behaviour' do
    it 'is a DRY RUN unless CONFIRM=1' do
      f = write_payload
      expect { run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path) }
        .not_to change { [Client.count, Family.count, Case.count] }
    end

    it 'is idempotent — a second run creates nothing new' do
      f = write_payload
      run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1')
      expect { run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1') }
        .not_to change { [Client.count, Family.count, Case.count] }
    end

    it 'MERGES into an existing form rather than replacing staff-entered values' do
      f = write_payload
      run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1')

      client = Client.find_by(code: 'SLO-FAMILY1-SPECPERSON')
      cf = CustomField.find_by(entity_type: 'Client', form_title: 'Adult: Employment')
      cfp = CustomFieldProperty.find_or_initialize_by(custom_field_id: cf.id,
                                                      custom_formable_type: 'Client',
                                                      custom_formable_id: client.id)
      cfp.properties = (cfp.properties || {}).merge('Volunteer Work' => 'added by staff')
      cfp.save!

      run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1')
      expect(cfp.reload.properties['Volunteer Work']).to eq('added by staff')
    end

    it 'skips a prospective household unless INCLUDE_PROSPECTIVE=1' do
      payload['households'] << { 'label' => 'Family 2', 'source_row' => 9, 'prospective' => true,
                                 'household' => {}, 'members' => [
                                   { 'source_row' => 10, 'given_name' => 'Prospect', 'family_name' => '',
                                     'person' => {}, 'overrides' => {} }
                                 ] }
      f = write_payload
      run_task('TENANT' => tenant, 'SLO_IMPORT_JSON' => f.path, 'CONFIRM' => '1')

      expect(Family.find_by(code: 'SLO-FAMILY2')).to be_nil
      expect(Family.find_by(code: 'SLO-FAMILY1')).to be_present
    end
  end
end
