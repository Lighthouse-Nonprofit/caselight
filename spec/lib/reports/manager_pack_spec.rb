# frozen_string_literal: true
require 'rails_helper'

# Reports batch R4 — the manager ops pack:
#   * CaseloadMovement: RS-51 algebra (active at start / new / exits / active at
#     end) with the exit-on-boundary rule (exit_date inside the range = an exit)
#   * WorkerCaseload: per-worker counts derived from case assignments
#   * Manager::FollowUpCompliance: program × worker overdue matrix + 30/60 buckets
#   * ServiceActivity: month bucketing + contacts-per-household rate
#   * EnrollmentDosage: cohort completer % via sidecar Present counts
RSpec.describe 'manager report pack' do
  PROPS4 = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  let(:period) do
    Reports::Period.new(preset: :custom, range: Date.new(2026, 6, 1)..Date.new(2026, 7, 31))
  end
  let(:program) { create(:program_stream, name: 'Employment') }

  def build(slug, klass, scope, **kwargs)
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: :manager, presets: %i[custom])
                                 .build(clients: scope, period: period, **kwargs)
  end

  describe Reports::Resettlement::CaseloadMovement do
    it 'computes start/new/exits/end with the boundary rules' do
      carried = create(:client, state: 'accepted')   # enrolled before, active throughout
      newcomer = create(:client, state: 'accepted')  # enrolls inside the period
      leaver = create(:client, state: 'accepted')    # enrolled before, exits ON period start

      create(:client_enrollment, client: carried, program_stream: program,
                                 enrollment_date: Date.new(2026, 1, 10))
      create(:client_enrollment, client: newcomer, program_stream: program,
                                 enrollment_date: Date.new(2026, 6, 15))
      leaving = create(:client_enrollment, client: leaver, program_stream: program,
                                           enrollment_date: Date.new(2026, 2, 1))
      LeaveProgram.create!(client_enrollment_id: leaving.id, program_stream_id: program.id,
                           exit_date: Date.new(2026, 6, 1), properties: {})

      scope = Client.where(id: [carried.id, newcomer.id, leaver.id])
      report = build('caseload-movement', 'Reports::Resettlement::CaseloadMovement', scope)
      row = report.sections.sole.rows.find { |r| r.first == 'Employment' }

      expect(row[1]).to eq(2) # active at start-1: carried + leaver (exit is 6/1, still active 5/31)
      expect(row[3]).to eq(1) # new: newcomer
      expect(row[4]).to eq(1) # exits: leaver (boundary date counts)
      expect(row[5]).to eq(2) # active at end: carried + newcomer
    end
  end

  describe Reports::Manager::WorkerCaseload do
    it 'counts per worker from case assignments and flags disabled accounts' do
      worker_a = create(:user, roles: 'case worker')
      worker_b = create(:user, roles: 'case worker')
      worker_b.update_columns(disable: true)
      client_a = create(:client, state: 'accepted', users: [worker_a])
      client_b = create(:client, state: 'accepted', users: [worker_b])
      enrollment = create(:client_enrollment, client: client_a, program_stream: program,
                                              enrollment_date: Date.new(2026, 6, 5))
      tracking = create(:tracking, name: 'Employment Progress', program_stream: program)
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Date.new(2026, 6, 20), properties: PROPS4)

      report = build('worker-caseloads', 'Reports::Manager::WorkerCaseload',
                     Client.where(id: [client_a.id, client_b.id]))
      rows = report.sections.sole.rows
      row_a = rows.find { |r| r.first == worker_a.name }
      row_b = rows.find { |r| r.first == worker_b.name }

      expect(row_a[1]).to eq(1)  # assigned
      expect(row_a[2]).to eq(1)  # active enrollments
      expect(row_a[3]).to eq(1)  # contacts in period
      expect(row_b[1]).to eq(1)
      expect(row_b[3]).to eq(0)
      expect(row_b.last).to eq(I18n.t('reports.registry.worker_caseloads.disabled_flag'))
    end
  end

  describe Reports::Manager::FollowUpCompliance do
    it 'aggregates overdue check-ins per program and worker' do
      worker = create(:user, roles: 'case worker')
      client = create(:client, state: 'accepted', users: [worker])
      tracking = create(:tracking, name: 'Monthly Check', frequency: 'Monthly', program_stream: program)
      enrollment = create(:client_enrollment, client: client, program_stream: program,
                                              enrollment_date: Time.zone.today - 100, status: 'Active')
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Time.zone.today - 50, properties: PROPS4)

      report = build('follow-up-compliance', 'Reports::Manager::FollowUpCompliance',
                     Client.where(id: client.id))
      matrix = report.sections.find { |s| s.key == :overdue_matrix }
      # the client factory may attach additional assigned users — assert the
      # worker's own row rather than the whole matrix
      expect(matrix.rows).to include(['Employment', worker.name, 1])
      expect(matrix.rows.map(&:first).uniq).to eq(['Employment'])

      buckets = report.sections.find { |s| s.key == :no_contact }
      thirty = buckets.rows.find { |r| r.first == I18n.t('reports.registry.follow_up_compliance.no_contact_30') }
      expect(thirty[1]).to eq(1)
    end
  end

  describe Reports::Resettlement::ServiceActivity do
    it 'buckets service units by month and computes the household rate' do
      client = create(:client, state: 'accepted')
      tracking = create(:tracking, name: 'Employment Progress', program_stream: program)
      enrollment = create(:client_enrollment, client: client, program_stream: program,
                                              enrollment_date: Date.new(2026, 5, 1), status: 'Active')
      [Date.new(2026, 6, 3), Date.new(2026, 6, 24), Date.new(2026, 7, 9)].each do |date|
        create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
               entry_date: date, properties: PROPS4)
      end

      report = build('service-activity', 'Reports::Resettlement::ServiceActivity',
                     Client.where(id: client.id))
      monthly = report.sections.find { |s| s.key == :monthly }
      row = monthly.rows.find { |r| r.first == 'Employment' }
      expect(row[1..2]).to eq([2, 1]) # Jun 26 = 2, Jul 26 = 1
      expect(monthly.chart[:type]).to eq(:line)

      rate = report.sections.find { |s| s.key == :rate }
      expect(rate.rows.sole[1]).to eq(3) # units
      expect(rate.rows.sole[2]).to eq(1) # single-person household
      expect(rate.rows.sole[3]).to eq(3.0)
    end
  end

  describe Reports::Youth::EnrollmentDosage do
    it 'computes completer % from sidecar Present counts' do
      cohort = create(:program_stream, name: 'Girasol')
      session = create(:tracking, name: 'Session Attendance', frequency: 'Weekly', program_stream: cohort)
      completer = create(:client, state: 'accepted')
      dropout = create(:client, state: 'accepted')
      e1 = create(:client_enrollment, client: completer, program_stream: cohort,
                                      enrollment_date: Date.new(2026, 6, 1))
      e2 = create(:client_enrollment, client: dropout, program_stream: cohort,
                                      enrollment_date: Date.new(2026, 6, 1))
      # completer: 3/3 present; dropout: 1/3 present
      3.times do |i|
        create(:client_enrollment_tracking, client_enrollment: e1, tracking: session,
               entry_date: Date.new(2026, 6, 5) + i * 7, properties: PROPS4.merge('Attendance' => 'Present'))
        create(:client_enrollment_tracking, client_enrollment: e2, tracking: session,
               entry_date: Date.new(2026, 6, 5) + i * 7,
               properties: PROPS4.merge('Attendance' => i.zero? ? 'Present' : 'Absent'))
      end

      report = build('enrollment-dosage', 'Reports::Youth::EnrollmentDosage',
                     Client.where(id: [completer.id, dropout.id]))
      row = report.sections.sole.rows.find { |r| r.first == 'Girasol' }
      expect(row[1]).to eq(2)      # youth served
      expect(row[2]).to eq(6)      # units
      expect(row.last).to eq('50%') # 1 of 2 enrollments at >= 75%
    end
  end
end
