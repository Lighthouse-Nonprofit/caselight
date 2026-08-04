# frozen_string_literal: true
require 'rails_helper'

# Reports batch — ServedSummary + YouthServed counting rules:
#   * unduplicated individuals vs duplicated service units (the ORR legend)
#   * households via KC cases; clients without a KC case = single-person household
#   * SERVED = enrolled-in-period ∪ contact-in-period
#   * zero-enrollment programs still render (funders require zeros)
#   * ability scoping: the report never sees clients outside the passed relation
RSpec.describe 'served summary reports' do
  # Tracking factory requires these labels (CustomFormPresentValidator).
  PROPS = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  let(:period) do
    Reports::Period.new(preset: :calendar_year,
                        range: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
  end
  let(:program) { create(:program_stream, name: 'Housing') }
  let(:empty_program) { create(:program_stream, name: 'Childcare') }
  let(:tracking) { create(:tracking, name: 'Monthly Housing Check', program_stream: program) }

  let!(:in_period_client) { create(:client, state: 'accepted') }
  let!(:contact_only_client) { create(:client, state: 'accepted') }
  let!(:out_of_scope_client) { create(:client, state: 'accepted') }

  def definition(slug, klass)
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: :leadership, presets: %i[calendar_year])
  end

  before do
    empty_program
    # enrolled inside the period, no contacts
    create(:client_enrollment, client: in_period_client, program_stream: program,
                               enrollment_date: Date.new(2026, 2, 1))
    # enrolled BEFORE the period but with two service contacts inside it
    old_enrollment = create(:client_enrollment, client: contact_only_client,
                            program_stream: program, enrollment_date: Date.new(2025, 3, 1))
    [Date.new(2026, 3, 10), Date.new(2026, 4, 12)].each do |date|
      create(:client_enrollment_tracking, client_enrollment: old_enrollment,
             tracking: tracking, entry_date: date, properties: PROPS)
    end
    # a third client enrolled in-period but OUTSIDE the report's client scope
    create(:client_enrollment, client: out_of_scope_client, program_stream: program,
                               enrollment_date: Date.new(2026, 5, 1))
  end

  it 'counts unduplicated individuals, households, and duplicated service units per program' do
    scope = Client.where(id: [in_period_client.id, contact_only_client.id])
    report = definition('served-summary', 'Reports::Resettlement::ServedSummary')
             .build(clients: scope, period: period)
    section = report.sections.sole
    housing = section.rows.find { |r| r.first == 'Housing' }
    childcare = section.rows.find { |r| r.first == 'Childcare' }
    total = section.rows.last

    expect(housing).to eq(['Housing', 2, 2, 2])   # 2 individuals, 2 single households, 2 units
    expect(childcare).to eq(['Childcare', 0, 0, 0]) # zero row still renders
    expect(total.first).to eq(I18n.t('reports.show.total'))
    expect(total[1]).to eq(2) # out-of-scope client NEVER counted
  end

  it 'groups household members into one household via the KC case' do
    fam = create(:family)
    [in_period_client, contact_only_client].each do |c|
      Case.create!(family: fam, client: c, case_type: 'KC', start_date: Date.new(2026, 1, 1))
    end
    scope = Client.where(id: [in_period_client.id, contact_only_client.id])
    report = definition('served-summary', 'Reports::Resettlement::ServedSummary')
             .build(clients: scope, period: period)
    housing = report.sections.sole.rows.find { |r| r.first == 'Housing' }
    expect(housing[2]).to eq(1) # one household now
  end

  # Adversarial-review fix: "new" = no service history BEFORE the period (the
  # VOCA convention). The previous version of this spec asserted the opposite for
  # a never-contacted youth — locking in a wrong number for funders.
  it 'YouthServed counts anyone with no PRIOR service history as new' do
    scope = Client.where(id: [in_period_client.id, contact_only_client.id])
    report = definition('youth-served', 'Reports::Youth::YouthServed')
             .build(clients: scope, period: period)
    nr = report.sections.find { |s| s.key == :new_returning }
    new_row = nr.rows.find { |r| r.first == I18n.t('reports.registry.youth_served.new_label') }
    returning_row = nr.rows.find { |r| r.first == I18n.t('reports.registry.youth_served.returning_label') }
    expect(new_row.last).to eq(2)      # neither had a contact before 2026-01-01
    expect(returning_row.last).to eq(0)
  end

  it 'YouthServed counts a youth with pre-period history as returning' do
    old_enrollment = ClientEnrollment.find_by(client_id: contact_only_client.id)
    create(:client_enrollment_tracking, client_enrollment: old_enrollment,
           tracking: tracking, entry_date: Date.new(2025, 11, 4), properties: PROPS)
    report = definition('youth-served', 'Reports::Youth::YouthServed')
             .build(clients: Client.where(id: contact_only_client.id), period: period)
    nr = report.sections.find { |s| s.key == :new_returning }
    returning_row = nr.rows.find { |r| r.first == I18n.t('reports.registry.youth_served.returning_label') }
    expect(returning_row.last).to eq(1)
  end
end
