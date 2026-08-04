# frozen_string_literal: true
require 'rails_helper'

# S5 — the tests the adversarial review said were missing. Each example fails
# against the pre-fix code, so they are real guards, not decoration.
RSpec.describe 'adversarial regressions' do
  APROPS = { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok' }.freeze

  def definition(slug, klass, audience: :leadership, presets: %i[calendar_year custom])
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: audience, presets: presets)
  end

  let(:year) do
    Reports::Period.new(preset: :calendar_year,
                        range: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
  end

  # P1 #1/#2/#14 — DecryptedScan must preserve the caller's ORDER BY. find_each
  # silently reorders by id, so a row entered out of date order flipped
  # "first/latest" everywhere.
  describe Reports::DecryptedScan do
    it 'yields in the relation order even when ids disagree with dates' do
      client = create(:client, state: 'accepted')
      program = create(:program_stream, name: 'Employment')
      tracking = create(:tracking, name: 'Employment Progress', program_stream: program)
      enrollment = create(:client_enrollment, client: client, program_stream: program,
                                              enrollment_date: Date.new(2026, 1, 1))
      # created LATER but dated EARLIER — id order is the inverse of date order
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Date.new(2026, 6, 1), properties: APROPS.merge('Status' => 'Searching'))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Date.new(2026, 1, 15), properties: APROPS.merge('Status' => 'Employed'))

      scope = ClientEnrollmentTracking.where(client_enrollment_id: enrollment.id)
                                      .order(:entry_date, :created_at)
      dates = Reports::DecryptedScan.each(scope).map { |record, _props| record.entry_date }
      expect(dates).to eq([Date.new(2026, 1, 15), Date.new(2026, 6, 1)])
    end
  end

  describe Reports::Resettlement::EmploymentOutcomes do
    it 'finds the earliest-DATED placement even when it was entered last' do
      client = create(:client, state: 'accepted')
      program = create(:program_stream, name: 'Employment')
      tracking = create(:tracking, name: 'Employment Progress', program_stream: program)
      enrollment = create(:client_enrollment, client: client, program_stream: program,
                                              enrollment_date: Date.new(2025, 12, 1))
      # entered in this order; the January placement is the LATER row
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Date.new(2026, 6, 10),
             properties: APROPS.merge('Status' => 'Employed', 'Hours per Week' => '40'))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: tracking,
             entry_date: Date.new(2026, 1, 20),
             properties: APROPS.merge('Status' => 'Employed', 'Hours per Week' => '40'))

      report = definition('employment-outcomes', 'Reports::Resettlement::EmploymentOutcomes')
               .build(clients: Client.where(id: client.id), period: year)
      rows = report.sections.sole.rows.to_h { |label, value| [label, value] }
      # placement = 2026-01-20, so day 90 (2026-04-20) falls INSIDE the year and
      # the June entry proves retention
      expect(rows[I18n.t('reports.registry.employment_outcomes.rows.retention_denominator')]).to eq(1)
      expect(rows[I18n.t('reports.registry.employment_outcomes.rows.retention_90')]).to eq('1 (100%)')
    end
  end

  describe Reports::Youth::AcademicPartner do
    it 'keeps baseline/current straight when entries are created out of order' do
      client = create(:client, state: 'accepted')
      pv = create(:program_stream, name: '¡Por Vida!')
      fields = [Reports::Youth::AcademicPartner::GPA_FIELD].each_with_index.map do |label, i|
        { 'name' => "g#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
      end
      aeries = create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
      enrollment = create(:client_enrollment, client: client, program_stream: pv,
                                              enrollment_date: Date.new(2026, 8, 15))
      # the LATER-dated row is created FIRST
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: aeries,
             entry_date: Date.new(2026, 11, 20),
             properties: { Reports::Youth::AcademicPartner::GPA_FIELD => '285' })
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: aeries,
             entry_date: Date.new(2026, 9, 1),
             properties: { Reports::Youth::AcademicPartner::GPA_FIELD => '250' })

      term = Reports::Period.new(preset: :term, range: Date.new(2026, 8, 1)..Date.new(2026, 12, 31))
      report = definition('academic-partner', 'Reports::Youth::AcademicPartner', presets: %i[term])
               .build(clients: Client.where(id: client.id), period: term)
      gpra = report.sections.find { |s| s.key == :gpra }
      expect(gpra.rows).to include([I18n.t('reports.registry.academic_partner.rows.gpa_improved'),
                                    '1 of 1 (100%)'])
      roster = report.sections.find { |s| s.key == :roster }
      expect(roster.rows.sole[1]).to eq('2.50 ↑ 2.85') # baseline → current, GPA-shaped
    end
  end

  # P1 #3 — schools map to the programs they host; they are not funders.
  describe Reports::FunderAttribution do
    it 'excludes kind=school agencies from funders and from the overlap buckets' do
      pv = create(:program_stream, name: '¡Por Vida!')
      funder = create(:agency, name: 'Elevate Youth CA')
      school = Agency.create!(name: 'Delta HS', kind: 'school')
      AgencyProgramStream.create!(agency: funder, program_stream: pv)
      AgencyProgramStream.create!(agency: school, program_stream: pv)
      client = create(:client, state: 'accepted')
      create(:client_enrollment, client: client, program_stream: pv,
                                 enrollment_date: Date.new(2026, 3, 1))

      report = definition('funder-attribution', 'Reports::FunderAttribution')
               .build(clients: Client.where(id: client.id), period: year)
      attribution = report.sections.find { |s| s.key == :attribution }
      expect(attribution.rows.map(&:first)).to eq(['Elevate Youth CA'])
      overlap = report.sections.find { |s| s.key == :overlap }
      one = overlap.rows.find { |r| r.first == I18n.t('reports.registry.funder_attribution.covered_by', count: '1') }
      two = overlap.rows.find { |r| r.first == I18n.t('reports.registry.funder_attribution.covered_by', count: '2') }
      expect(one.last).to eq(1)
      expect(two.last).to eq(0) # the school must not add a phantom second funder
    end
  end

  # P1 #4 — a truncated ?period= is a fallback, not a 500.
  describe Reports::Period do
    it 'falls back when the period param carries no dates' do
      defn = definition('served-summary', 'Reports::Resettlement::ServedSummary',
                        presets: %i[ffy custom])
      expect { Reports::Period.resolve(defn, { period: 'ffy' }) }.not_to raise_error
      expect(Reports::Period.resolve(defn, { period: 'ffy' }).preset).to eq(:ffy)
      expect(Reports::Period.resolve(defn, { period: 'ffy|2026-01-01' }).preset).to eq(:ffy)
    end
  end

  # P2 #7 — cohort attendance % must ignore non-session trackings.
  describe Reports::Worker::CaseloadDosage do
    it 'counts only Session Attendance entries in the attendance denominator' do
      worker = create(:user, roles: 'case worker')
      client = create(:client, state: 'accepted', users: [worker])
      cohort = create(:program_stream, name: 'Girasol')
      session = create(:tracking, name: 'Session Attendance', frequency: 'Weekly',
                                  time_of_frequency: 1, program_stream: cohort)
      other = create(:tracking, name: 'Wellness Check', program_stream: cohort)
      enrollment = create(:client_enrollment, client: client, program_stream: cohort,
                                              enrollment_date: Date.new(2026, 2, 1), properties: APROPS)
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: session,
             entry_date: Date.new(2026, 3, 4), properties: APROPS.merge('Attendance' => 'Present'))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: other,
             entry_date: Date.new(2026, 3, 5), properties: APROPS)

      report = definition('my-youth-dosage', 'Reports::Worker::CaseloadDosage', audience: :worker)
               .build(clients: Client.where(id: client.id), period: year)
      row = report.sections.find { |s| s.key == :cohorts }.rows.sole
      expect(row[3]).to eq(1)       # sessions logged — the Wellness Check must not count
      expect(row[4]).to eq('100%')
    end
  end

  # P2 #13 — dynamic sections carry real titles into CSV/PDF.
  describe 'dynamic section titles' do
    it 'names quantitative sections after the list, not a humanized key' do
      qt = QuantitativeType.create!(name: 'Preferred Language')
      qt.quantitative_cases.create!(value: 'Mixteco')
      report = definition('demographics', 'Reports::Youth::Demographics')
               .build(clients: Client.none, period: year)
      titles = report.sections.map { |section| report.section_title(section) }
      expect(titles).to include('Preferred Language')
      expect(titles).not_to include('Quant preferred language')
      expect(report.to_csv).to include('Preferred Language')
    end
  end

  # P2 #20 — a KC case with no family must not vanish from household totals.
  describe 'household counting' do
    it 'counts a KC case with a NULL family as a single-person household' do
      program = create(:program_stream, name: 'Housing')
      client = create(:client, state: 'accepted')
      create(:client_enrollment, client: client, program_stream: program,
                                 enrollment_date: Date.new(2026, 2, 2))
      Case.new(client: client, case_type: 'KC', start_date: Date.new(2026, 2, 2))
          .save(validate: false) # family_id NULL — legacy/partial data
      report = definition('served-summary', 'Reports::Resettlement::ServedSummary')
               .build(clients: Client.where(id: client.id), period: year)
      housing = report.sections.sole.rows.find { |r| r.first == 'Housing' }
      expect(housing[1]).to eq(1) # individuals
      expect(housing[2]).to eq(1) # households — was 0 before the fix
    end
  end

  # P3 #21 — the two reports that had no test at all: prove they build and
  # render against empty and minimal data instead of crashing.
  describe 'previously untested youth reports' do
    it 'SelOutcomes builds with zero clients and with a single unmatched assessment' do
      create(:domain, name: 'Y1', identity: 'Self-Awareness', sensitivity: 'standard')
      empty = definition('sel-outcomes', 'Reports::Youth::SelOutcomes')
              .build(clients: Client.none, period: year)
      expect { empty.sections }.not_to raise_error
      expect(empty.to_csv).to be_present

      client = create(:client, state: 'accepted')
      create(:assessment, client: client, created_at: Date.new(2026, 3, 1))
      report = definition('sel-outcomes', 'Reports::Youth::SelOutcomes')
               .build(clients: Client.where(id: client.id), period: year,
                      visible_domain_levels: %w[standard])
      coverage = report.sections.find { |s| s.key == :coverage }
      assessed = coverage.rows.find { |r| r.first == I18n.t('reports.registry.sel_outcomes.rows.assessed') }
      pairs = coverage.rows.find { |r| r.first == I18n.t('reports.registry.sel_outcomes.rows.matched_pairs') }
      expect(assessed.last).to eq(1)
      expect(pairs.last).to eq(0) # one assessment is coverage, never an outcome
      movement = report.sections.find { |s| s.key == :movement }
      expect(movement.rows.map(&:first)).to include('Self-Awareness')
    end

    it 'youth Demographics builds with no quantitative types and no clients' do
      report = definition('demographics', 'Reports::Youth::Demographics')
               .build(clients: Client.none, period: year)
      expect { report.sections }.not_to raise_error
      # zero counts still REPORT (a funder reads a missing band as unreported)
      expect(report.to_csv).to include('Age 0-4,0')
      expect(report.to_csv).to include(report.title)
    end

    it 'youth Demographics carries its own title, not the resettlement wording' do
      youth = Reports::Registry.find!('demographics', flavor: 'youth')
      resettlement = Reports::Registry.find!('demographics', flavor: 'resettlement')
      expect(youth.klass_name).to eq('Reports::Youth::Demographics')
      expect(resettlement.klass_name).to eq('Reports::Resettlement::Demographics')
      overlay = YAML.load_file(Rails.root.join('config', 'flavors', 'youth', 'en.yml'))
      expect(overlay.dig('en', 'reports', 'registry', 'demographics', 'title')).to be_present
      expect(overlay.dig('en', 'reports', 'registry', 'demographics', 'description')).to be_present
    end
  end
end
