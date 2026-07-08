# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U2) — POAM-SC28-HIST part A. paper_trail serializes DECRYPTED attribute values, so
# without skip: lists the versions table is a plaintext shadow copy of every Phase-4-encrypted
# column. Contract proven here:
#   1. DRIFT GUARD (load-bearing): every versioned model skips ALL of its encrypted attributes.
#      The skip lists are literal (has_paper_trail runs before the encrypts declarations), so this
#      spec is what fails CI when someone adds `encrypts` without a matching skip entry.
#   2. Redaction: changed PII never appears in object_changes; destroy versions carry no PII;
#      reify still works from the surviving keys.
#   3. Who/when restoration (RedactedUpdateVersions): paper_trail's skip implies ignore — a save
#      changing ONLY skipped attrs would write NO version. The concern force-records a values-free
#      update version so the AU-3 who-changed-what-when trail survives redaction.
RSpec.describe 'paper_trail PII redaction', type: :model do
  after(:each) { ClientHistory.delete_all rescue nil }

  describe 'drift guard: encrypted attributes are always skipped' do
    it 'covers every versioned model with encrypted attributes' do
      Rails.application.eager_load!
      versioned = ActiveRecord::Base.descendants.select do |klass|
        klass.respond_to?(:paper_trail_options) && klass.paper_trail_options.present?
      end
      expect(versioned).not_to be_empty

      offenders = versioned.each_with_object({}) do |klass, bad|
        encrypted = Array(klass.try(:encrypted_attributes)).map(&:to_s)
        next if encrypted.empty?
        skipped = Array(klass.paper_trail_options[:skip]).map(&:to_s)
        missing = encrypted - skipped
        bad[klass.name] = missing if missing.any?
      end

      expect(offenders).to be_empty,
        "encrypted attributes not in has_paper_trail skip: (add them): #{offenders.inspect}"
    end

    it 'skips credential material on User even beyond encrypted_attributes' do
      skipped = Array(User.paper_trail_options[:skip]).map(&:to_s)
      expect(skipped).to include('encrypted_password', 'otp_backup_codes', 'tokens',
                                 'reset_password_token', 'unlock_token')
    end
  end

  describe 'Client version redaction' do
    let!(:client) { create(:client, given_name: 'RedactedGiven', status: 'Referred') }

    it 'omits PII from object_changes but keeps non-PII changes' do
      client.update!(given_name: 'ChangedGiven', state: 'accepted')
      version = client.versions.reorder(:created_at, :id).last
      expect(version.event).to eq('update')
      expect(version.changeset.keys).to include('state')
      expect(version.changeset.keys).not_to include('given_name')
      expect(version.object_changes.to_s).not_to include('ChangedGiven')
    end

    it 'writes a destroy version with no PII payload and a working reify' do
      slug = client.slug
      client.destroy!
      version = PaperTrail::Version.where(item_type: 'Client', item_id: client.id, event: 'destroy').last
      expect(version).to be_present
      expect(version.object.to_s).not_to include('RedactedGiven')
      expect(version.object.to_s).to include(slug)
      expect(version.reify.slug).to eq(slug)
    end

    it 'still records who/when for a PII-only edit (values-free forced version)' do
      expect {
        client.update!(given_name: 'OnlyPiiChanged')
      }.to change { client.versions.where(event: 'update').count }.by(1)

      version = client.versions.where(event: 'update').reorder(:created_at, :id).last
      expect(version.object.to_s).not_to include('RedactedGiven')     # pre-change value redacted
      expect(version.object_changes.to_s).not_to include('OnlyPiiChanged')
      expect(version.changeset.keys - %w[updated_at]).to be_empty
    end

    it 'does not double-record when PII and non-PII change together' do
      expect {
        client.update!(given_name: 'Mixed', state: 'accepted')
      }.to change { client.versions.where(event: 'update').count }.by(1)
    end
  end

  describe 'CustomFieldProperty (Tier-5 properties) version redaction' do
    let!(:custom_field) do
      create(:custom_field, entity_type: 'Client', form_title: 'PT Redaction Form',
             fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
    end
    let!(:client) { create(:client) }
    let!(:cfp) do
      create(:custom_field_property, custom_field: custom_field, custom_formable: client,
             properties: { 'Diagnosis' => 'CFP_V1_SENTINEL' })
    end

    it 'records a values-free who/when version for a properties-only save' do
      expect {
        cfp.update!(properties: { 'Diagnosis' => 'CFP_V2_SENTINEL' })
      }.to change { cfp.versions.where(event: 'update').count }.by(1)

      version = cfp.versions.where(event: 'update').reorder(:created_at, :id).last
      expect(version.object.to_s).not_to include('CFP_V1_SENTINEL')
      expect(version.object_changes.to_s).not_to include('CFP_V2_SENTINEL')
      # custom_field_id survives in the payload — SensitiveVersionScope keys on it.
      expect(version.object.to_s).to include('custom_field_id')
    end

    it 'keeps properties out of the create version' do
      create_version = cfp.versions.where(event: 'create').last
      expect(create_version).to be_present
      expect(create_version.object_changes.to_s).not_to include('CFP_V1_SENTINEL')
    end
  end

  describe 'User version redaction' do
    let!(:user) { create(:user, first_name: 'StaffRedact') }

    it 'omits Tier-3 staff PII and credential material from version payloads' do
      user.update!(first_name: 'StaffChanged', job_title: 'Case Supervisor')
      version = user.versions.reorder(:created_at, :id).last
      expect(version.changeset.keys).to include('job_title')
      expect(version.changeset.keys).not_to include('first_name')
      expect(version.object_changes.to_s).not_to include('StaffChanged')
      expect(version.object.to_s).not_to include(user.email)
      expect(version.object.to_s).not_to include('encrypted_password')
    end
  end
end
