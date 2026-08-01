# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Reports batch R6 — AOGP employment math:
#   * FT at exactly 35 hours (boundary), explicit Employment Type overrides hours
#   * placement date prefers Job Start Date over the entry's service date
#   * average wage over FT placements only; benefits % over all placements
#   * 90-day retention: any later Employed entry counts; the denominator only
#     includes placements whose day-90 falls INSIDE the period
#   * seed re-run: the new AOGP fields land additively on an existing tracking
RSpec.describe Reports::Resettlement::EmploymentOutcomes do
  EPROPS = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  let(:period) do
    Reports::Period.new(preset: :calendar_year,
                        range: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
  end
  let(:program) { create(:program_stream, name: 'Employment') }
  let(:tracking) { create(:tracking, name: 'Employment Progress', program_stream: program) }

  def enroll_with_entry(client, entry_date, props)
    enrollment = create(:client_enrollment, client: client, program_stream: program,
                                            enrollment_date: entry_date - 30)
    create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
           entry_date: entry_date, properties: EPROPS.merge(props))
    enrollment
  end

  def build(scope)
    Reports::Registry::Definition.new(slug: 'employment-outcomes',
                                      klass_name: 'Reports::Resettlement::EmploymentOutcomes',
                                      audience: :leadership, presets: %i[calendar_year])
                                 .build(clients: scope, period: period)
  end

  def row(report, key)
    report.sections.sole.rows.find { |r| r.first == I18n.t("reports.registry.employment_outcomes.rows.#{key}") }
  end

  it 'classifies FT at exactly 35 hours and lets Employment Type override hours' do
    exactly35 = create(:client, state: 'accepted')
    typed_pt = create(:client, state: 'accepted')
    enroll_with_entry(exactly35, Date.new(2026, 3, 2),
                      'Status' => 'Employed', 'Hours per Week' => '35', 'Hourly Wage (USD)' => '18.50')
    enroll_with_entry(typed_pt, Date.new(2026, 4, 6),
                      'Status' => 'Employed', 'Hours per Week' => '40',
                      'Employment Type' => 'Part-time (<35 hrs/wk)', 'Health Benefits Offered' => 'Yes')

    report = build(Client.where(id: [exactly35.id, typed_pt.id]))
    expect(row(report, :entered_employment).last).to eq(2)
    expect(row(report, :full_time).last).to eq(1)      # 35 hrs = FT; explicit PT overrides 40 hrs
    expect(row(report, :part_time).last).to eq(1)
    expect(row(report, :avg_wage_ft).last).to eq('$18.5')
    expect(row(report, :benefits_offered).last).to eq('1 (50%)')
  end

  it 'prefers Job Start Date and computes 90-day retention with the honest denominator' do
    retained_client = create(:client, state: 'accepted')
    lost_client = create(:client, state: 'accepted')
    pending_client = create(:client, state: 'accepted')

    # placement 2026-01-15 (via Job Start Date on a later-dated entry), retained at day 95
    enrollment = enroll_with_entry(retained_client, Date.new(2026, 2, 1),
                                   'Status' => 'Employed', 'Hours per Week' => '40',
                                   'Job Start Date' => '2026-01-15')
    create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
           entry_date: Date.new(2026, 4, 20), properties: EPROPS.merge('Status' => 'Employed'))

    # placement 2026-02-01, later entry says Searching -> NOT retained
    lost_e = enroll_with_entry(lost_client, Date.new(2026, 2, 1),
                               'Status' => 'Employed', 'Hours per Week' => '40')
    create(:client_enrollment_tracking, client_enrollment: lost_e, tracking: tracking,
           entry_date: Date.new(2026, 6, 1), properties: EPROPS.merge('Status' => 'Searching'))

    # placement 2026-11-15: day-90 falls in 2027 -> excluded from the denominator
    enroll_with_entry(pending_client, Date.new(2026, 11, 15),
                      'Status' => 'Employed', 'Hours per Week' => '40')

    report = build(Client.where(id: [retained_client.id, lost_client.id, pending_client.id]))
    expect(row(report, :entered_employment).last).to eq(3)
    expect(row(report, :retention_denominator).last).to eq(2) # pending excluded
    expect(row(report, :retention_90).last).to eq('1 (50%)')
  end

  describe 'seed additions' do
    it 're-running slo4home:seed_programs adds the AOGP fields additively' do
      Rake.application.rake_require('tasks/slo4home_taxonomy', [Rails.root.join('lib').to_s]) unless Rake::Task.task_defined?('slo4home:seed_programs')
      Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
      ENV['TENANT'] = Apartment::Tenant.current
      2.times do
        Rake::Task['slo4home:seed_programs'].reenable
        saved = $stdout
        $stdout = StringIO.new
        Rake::Task['slo4home:seed_programs'].invoke
        $stdout = saved
      end
      ENV.delete('TENANT')

      seeded = ProgramStream.find_by(name: 'Employment').trackings.find_by(name: 'Employment Progress')
      labels = seeded.fields.map { |f| f['label'] }
      expect(labels).to include('Employment Type', 'Health Benefits Offered', 'Job Start Date')
      expect(labels.count('Notes')).to eq(1) # no duplication on re-run
    end
  end
end
