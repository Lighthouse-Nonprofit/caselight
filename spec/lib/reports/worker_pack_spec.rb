# frozen_string_literal: true
require 'rails_helper'

# Reports batch R3 — the worker tier:
#   * CaseloadProgress: first-vs-latest assessment movement over VISIBLE domains
#     only (restricted domains never leak into a standard-only viewer's averages)
#   * FollowUpCompliance: cadence grace windows (Monthly 35d) drive overdue rows
#   * CaseloadDosage: cohort attendance % from sidecar Present counts
#   * roster policy: strategic overviewer sees anonymous ids, never names
RSpec.describe 'worker report pack' do
  PROPS3 = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  let(:period) do
    Reports::Period.new(preset: :custom, range: (Time.zone.today - 90)..Time.zone.today)
  end
  let(:worker) { create(:user, roles: 'case worker') }
  let!(:client) { create(:client, given_name: 'Prog', family_name: 'Ress', state: 'accepted', users: [worker]) }

  def build(slug, klass, scope, **kwargs)
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: :worker, presets: %i[custom])
                                 .build(clients: scope, period: period, **kwargs)
  end

  describe Reports::Worker::CaseloadProgress do
    let!(:standard_domain) { create(:domain, name: 'S1', sensitivity: 'standard') }
    let!(:restricted_domain) { create(:domain, name: 'R1', sensitivity: 'restricted') }

    before do
      # the assessment-interval gate (Y2c) blocks a second assessment inside 6
      # calendar months — space the pair beyond it
      first = create(:assessment, client: client, created_at: 220.days.ago)
      latest = create(:assessment, client: client, created_at: 5.days.ago)
      create(:assessment_domain, assessment: first, domain: standard_domain, score: 1)
      create(:assessment_domain, assessment: latest, domain: standard_domain, score: 3)
      # restricted domain crashes the average only if it leaks past masking:
      create(:assessment_domain, assessment: first, domain: restricted_domain, score: 4)
      create(:assessment_domain, assessment: latest, domain: restricted_domain, score: 1)
    end

    it 'computes movement over visible domains only (standard-only viewer)' do
      report = build('my-caseload-progress', 'Reports::Worker::CaseloadProgress',
                     Client.where(id: client.id),
                     visible_domain_levels: [SensitivityPolicy::STANDARD])
      row = report.sections.sole.rows.sole
      expect(row[4]).to eq(1.0)  # first avg: standard domain only
      expect(row[5]).to eq(3.0)  # latest avg
      expect(row[6]).to eq(2.0)  # improved — the restricted regression is invisible
      expect(report.sections.sole.footnote).to include('1 of 1')
    end

    it 'includes the restricted movement for an all-levels viewer (admin)' do
      report = build('my-caseload-progress', 'Reports::Worker::CaseloadProgress',
                     Client.where(id: client.id),
                     visible_domain_levels: %w[standard restricted emergency_only])
      row = report.sections.sole.rows.sole
      expect(row[4]).to eq(2.5) # (1+4)/2
      expect(row[5]).to eq(2.0) # (3+1)/2
    end
  end

  describe Reports::Worker::FollowUpCompliance do
    let(:program) { create(:program_stream, name: 'Housing') }
    let!(:tracking) { create(:tracking, name: 'Monthly Housing Check', frequency: 'Monthly', program_stream: program) }
    let!(:enrollment) do
      create(:client_enrollment, client: client, program_stream: program,
                                 enrollment_date: Time.zone.today - 80, status: 'Active')
    end

    it 'flags a Monthly check-in whose last entry is beyond the 35-day grace' do
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Time.zone.today - 40, properties: PROPS3)
      report = build('my-follow-up-compliance', 'Reports::Worker::FollowUpCompliance',
                     Client.where(id: client.id))
      overdue = report.sections.find { |s| s.key == :overdue_checkins }
      expect(overdue.rows.sole[2]).to eq('Monthly Housing Check')
      expect(overdue.rows.sole.last).to eq(5) # 40 - 35
    end

    it 'stays quiet inside the grace window and lists 30-day no-contact' do
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Time.zone.today - 31, properties: PROPS3)
      report = build('my-follow-up-compliance', 'Reports::Worker::FollowUpCompliance',
                     Client.where(id: client.id))
      expect(report.sections.find { |s| s.key == :overdue_checkins }.rows).to be_empty
      no_contact = report.sections.find { |s| s.key == :no_contact }
      expect(no_contact.rows.sole.last).to eq(31)
    end

    it 'anonymizes the roster for a strategic overviewer viewer' do
      overviewer = create(:user, roles: 'strategic overviewer')
      report = build('my-follow-up-compliance', 'Reports::Worker::FollowUpCompliance',
                     Client.where(id: client.id), viewer: overviewer)
      no_contact = report.sections.find { |s| s.key == :no_contact }
      expect(no_contact.rows.sole.first).to eq("##{client.id}")
      expect(no_contact.rows.sole.first).not_to include('Prog')
    end
  end

  describe Reports::Worker::CaseloadDosage do
    let(:cohort) { create(:program_stream, name: 'Girasol') }
    let!(:session_tracking) do
      create(:tracking, name: 'Session Attendance', frequency: 'Weekly', program_stream: cohort)
    end
    let!(:enrollment) do
      create(:client_enrollment, client: client, program_stream: cohort,
                                 enrollment_date: Time.zone.today - 30, status: 'Active')
    end

    it 'computes attendance % from sidecar Present counts' do
      [['Present', 10], ['Present', 17], ['Absent', 24]].each do |value, days_ago|
        create(:client_enrollment_tracking, client_enrollment: enrollment,
               tracking: session_tracking, entry_date: Time.zone.today - days_ago,
               properties: PROPS3.merge('Attendance' => value))
      end
      report = build('my-youth-dosage', 'Reports::Worker::CaseloadDosage',
                     Client.where(id: client.id))
      row = report.sections.find { |s| s.key == :cohorts }.rows.sole
      expect(row[2]).to eq(2)      # present
      expect(row[3]).to eq(3)      # sessions logged
      expect(row[4]).to eq('67%')
    end
  end
end
