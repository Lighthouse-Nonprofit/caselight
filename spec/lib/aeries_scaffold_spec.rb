# frozen_string_literal: true
require 'rails_helper'

# SCH3 — the Aeries scaffold's security + mapping contract:
#   * disabled by default; https-only; host-pinned
#   * matching via the sidecar Student ID field (deterministic equality)
#   * idempotent per (enrollment, report date); dry-run writes nothing
RSpec.describe 'Aeries scaffold' do
  describe Aeries::Client do
    it 'is disabled without credentials and refuses to call' do
      expect(described_class.enabled?).to be(false)
      expect { described_class.new.get('api/v5/schools') }.to raise_error(Aeries::Client::Disabled)
    end

    it 'rejects a non-https base even when configured' do
      ENV['AERIES_BASE_URL'] = 'http://demo.aeries.net/aeries'
      ENV['AERIES_API_KEY'] = 'test-key'
      expect { described_class.new.get('api/v5/schools') }.to raise_error(Aeries::Client::InsecureEndpoint)
    ensure
      ENV.delete('AERIES_BASE_URL')
      ENV.delete('AERIES_API_KEY')
    end
  end

  describe Aeries::AcademicSync do
    let(:pv) { create(:program_stream, name: '¡Por Vida!') }
    let!(:aeries_tracking) do
      fields = ['GPA (x100, e.g. 275 = 2.75)', 'Credits Earned (cumulative)', 'A-G On Track',
                'School-Day Attendance % (this period)', 'Discipline Incidents (this period)'].each_with_index.map do |label, i|
        { 'name' => "a#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
      end
      create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
    end
    let(:form) do
      CustomField.create!(entity_type: 'Client', form_title: 'Referral & Intake',
                          fields: [{ 'type' => 'text', 'label' => 'Student ID (Aeries)' }])
    end
    let(:youth) { create(:client, state: 'accepted') }
    let!(:enrollment) do
      create(:client_enrollment, client: youth, program_stream: pv,
                                 enrollment_date: Time.zone.today - 60, status: 'Active')
    end
    let(:record) do
      { 'StudentID' => '998877', 'ReportDate' => '2026-11-01', 'GPA' => 2.85,
        'CreditsEarned' => 120, 'AttendancePercent' => 93.0,
        'DisciplineIncidents' => 0, 'AGOnTrack' => true }
    end

    before do
      CustomFieldProperty.create!(custom_field_id: form.id, custom_formable_type: 'Client',
                                  custom_formable_id: youth.id,
                                  properties: { 'Student ID (Aeries)' => '998877' })
    end

    it 'dry-run matches via the sidecar but writes nothing' do
      result = described_class.new([record]).run!
      expect(result.dry_run).to be(true)
      expect(result.matched).to eq(1)
      expect(ClientEnrollmentTracking.count).to eq(0)
    end

    it 'confirmed run creates one x100-GPA entry, idempotently' do
      result = described_class.new([record], confirm: true).run!
      expect(result.created).to eq(1)
      entry = ClientEnrollmentTracking.sole
      expect(entry.entry_date).to eq(Date.new(2026, 11, 1))
      expect(entry.properties['GPA (x100, e.g. 275 = 2.75)']).to eq('285')
      expect(entry.properties['A-G On Track']).to eq('On track')

      rerun = described_class.new([record], confirm: true).run!
      expect(rerun.skipped_existing).to eq(1)
      expect(ClientEnrollmentTracking.count).to eq(1)
    end

    it 'counts unknown student ids as unmatched without raising' do
      result = described_class.new([record.merge('StudentID' => '000000')], confirm: true).run!
      expect(result.unmatched).to eq(1)
      expect(result.created).to eq(0)
    end
  end
end
