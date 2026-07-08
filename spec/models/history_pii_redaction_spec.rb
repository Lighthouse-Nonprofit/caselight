# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U3) — POAM-SC28-HIST part B. The Mongo history snapshots stored full DECRYPTED attribute
# hashes (client PII, staff emails/credentials/sign-in IPs, custom-form values) in the shared
# history database. Contract: new snapshots carry ids/statuses/dates/association keys only.
RSpec.describe 'Mongo history PII redaction', type: :model do
  after(:each) do
    ClientHistory.delete_all rescue nil
    TaskHistory.delete_all rescue nil
  end

  let!(:worker) { create(:user, roles: 'case worker', first_name: 'StaffSecret', mobile: '+85512345678') }

  describe 'ClientHistory.initial' do
    let!(:client) do
      create(:client, given_name: 'MongoSecret', current_address: 'MONGO_ADDR_SENTINEL',
             users: [worker])
    end

    it 'scrubs encrypted client attributes but keeps ids/status/slug and association keys' do
      history = ClientHistory.unscoped.where('object.id' => client.id).last
      expect(history).to be_present
      expect(history.object.keys).to include('id', 'status', 'slug', 'user_ids')
      expect(history.object.keys).not_to include('given_name', 'family_name', 'current_address',
                                                 'background', 'reason_for_referral')
      expect(history.object.to_s).not_to include('MongoSecret', 'MONGO_ADDR_SENTINEL')
    end

    it 'scrubs every embedded staff snapshot (email/names/credentials/IPs gone; id/roles kept)' do
      history = ClientHistory.unscoped.where('object.id' => client.id).last
      staff_snapshots = history.case_worker_client_histories.to_a
      expect(staff_snapshots).not_to be_empty
      staff_snapshots.each do |staff|
        expect(staff.object['id']).to be_present
        expect(staff.object['roles']).to be_present
        %w[email first_name last_name mobile encrypted_password otp_secret
           current_sign_in_ip last_sign_in_ip tokens].each do |key|
          expect(staff.object.keys).not_to include(key), "expected staff snapshot to omit #{key}"
        end
      end
      # The whole history document (incl. every embedded snapshot) carries no staff-name sentinel.
      expect(history.attributes.to_s).not_to include('StaffSecret')
    end

    it 'scrubs the embedded custom-field snapshot (properties gone, custom_field_id kept)' do
      cf = create(:custom_field, entity_type: 'Client', form_title: 'Mongo Redaction Form',
                  fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
      create(:custom_field_property, custom_field: cf, custom_formable: client,
             properties: { 'Diagnosis' => 'CFP_MONGO_SENTINEL' })

      history = ClientHistory.unscoped.where('object.id' => client.id).last
      cfp_hist = history.client_custom_field_property_histories.last
      expect(cfp_hist).to be_present
      expect(cfp_hist.object['custom_field_id']).to eq(cf.id)
      expect(cfp_hist.object.keys).not_to include('properties')
      expect(cfp_hist.object.to_s).not_to include('CFP_MONGO_SENTINEL')
    end

    it 'scrubs the embedded family snapshot (encrypted narrative/address gone, name kept)' do
      family = create(:family, name: 'Mongo Household', caregiver_information: 'FAM_MONGO_SENTINEL')
      create(:case, client: client, family: family, case_type: 'KC')

      # A fresh save snapshots the now-linked family.
      client.reload.save!
      history = ClientHistory.unscoped.where('object.id' => client.id).last
      fam_hist = history.client_family_histories.last
      expect(fam_hist).to be_present
      expect(fam_hist.object['name']).to eq('Mongo Household')
      expect(fam_hist.object.keys).not_to include('caregiver_information', 'case_history', 'address')
      expect(fam_hist.object.to_s).not_to include('FAM_MONGO_SENTINEL')
    end
  end

  describe 'TaskHistory.initial' do
    let!(:client) { create(:client, users: [worker]) }
    let!(:task)   { create(:task, client: client, name: 'Follow up', completion_date: Date.current) }

    it 'keeps the StaffMonthlyReport contract keys and scrubs the staff snapshot' do
      TaskHistory.delete_all rescue nil
      TaskHistory.initial(task)

      history = TaskHistory.unscoped.last
      expect(history.object['completion_date']).to be_present
      expect(history.object).to have_key('completed')
      expect(history.object['user_ids']).to be_an(Array)
      expect(history.object['user_ids']).not_to be_empty

      staff_snapshots = history.case_worker_task_histories.to_a
      expect(staff_snapshots).not_to be_empty
      staff_snapshots.each do |staff|
        expect(staff.object.keys).not_to include('email', 'first_name', 'mobile',
                                                 'encrypted_password', 'current_sign_in_ip')
      end
    end
  end
end
