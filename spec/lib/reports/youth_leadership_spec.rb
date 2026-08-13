# frozen_string_literal: true
require 'rails_helper'

# Reports batch R7 — the youth leadership pack:
#   * CohortCompletion: sidecar Term roster, 75%-of-curriculum thresholds
#     (9/12, 10/13), completion rate
#   * StopTheHateQuarterly: RESTRICTED gating — the bias table renders only for
#     a viewer whose visible_custom_field_ids admits the Hate Incident form;
#     everyone else gets restricted_hidden and NO category values in ANY format
#   * AcademicPartner: label-exact Aeries fields, x100 GPA baseline math
RSpec.describe 'youth leadership pack' do
  YPROPS = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  let(:term_period) do
    Reports::Period.new(preset: :term, range: Date.new(2026, 8, 1)..Date.new(2026, 12, 31))
  end

  def definition(slug, klass, presets: %i[term custom])
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: :leadership, presets: presets)
  end

  describe Reports::Youth::CohortCompletion do
    it 'builds the Term roster via sidecar equality and applies the 10/13 Girasol threshold' do
      girasol = create(:program_stream, name: 'Girasol')
      session = create(:tracking, name: 'Session Attendance', frequency: 'Weekly', program_stream: girasol)
      in_term = create(:client, given_name: 'Ines', family_name: 'Term', state: 'accepted')
      off_term = create(:client, given_name: 'Oscar', family_name: 'Off', state: 'accepted')
      e_in = create(:client_enrollment, client: in_term, program_stream: girasol,
                                        enrollment_date: Date.new(2026, 8, 20),
                                        properties: YPROPS.merge('Site' => 'Delta HS', 'Term' => 'Fall 26'))
      create(:client_enrollment, client: off_term, program_stream: girasol,
                                 enrollment_date: Date.new(2026, 1, 15),
                                 properties: YPROPS.merge('Site' => 'Delta HS', 'Term' => 'Spring 26'))
      10.times do |i|
        create(:client_enrollment_tracking, client_enrollment: e_in, tracking: session,
               entry_date: Date.new(2026, 9, 1) + i * 7,
               properties: YPROPS.merge('Attendance' => 'Present'))
      end

      report = definition('cohort-completion', 'Reports::Youth::CohortCompletion')
               .build(clients: Client.where(id: [in_term.id, off_term.id]), period: term_period)
      section = report.sections.find { |s| s.key == :cohort_girasol }
      expect(section.rows.size).to eq(1) # Spring-26 enrollment excluded from the Fall-26 roster
      expect(section.rows.sole[1]).to eq(10)
      expect(section.rows.sole[2]).to eq(13)
      expect(section.rows.sole[3]).to eq(I18n.t('reports.registry.cohort_completion.completer')) # 10 >= ceil(13*0.75)=10
      expect(section.footnote).to include('100%')
      expect(section.footnote).to include('Fall 26')
    end
  end

  describe Reports::Youth::StopTheHateQuarterly do
    let(:sth) { create(:program_stream, name: 'Stop The Hate') }
    let!(:nav) { create(:tracking, name: 'Navigation / Case Mgmt / Referral', program_stream: sth) }
    let(:form) do
      CustomField.create!(entity_type: 'Client', form_title: 'Hate Incident Record',
                          fields: [{ 'type' => 'select', 'label' => 'Bias Category' },
                                   { 'type' => 'date', 'label' => 'Incident Date' }],
                          sensitivity: 'restricted')
    end
    let(:victim) { create(:client, state: 'accepted') }
    let(:quarter) do
      Reports::Period.new(preset: :sfy_quarter, range: Date.new(2026, 7, 1)..Date.new(2026, 9, 30))
    end

    before do
      enrollment = create(:client_enrollment, client: victim, program_stream: sth,
                                              enrollment_date: Date.new(2026, 7, 10))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: nav,
             entry_date: Date.new(2026, 8, 2), properties: YPROPS)
      CustomFieldProperty.create!(custom_field_id: form.id, custom_formable_type: 'Client',
                                  custom_formable_id: victim.id,
                                  properties: { 'Bias Category' => 'National origin',
                                                'Incident Date' => '2026-08-01' })
    end

    def build_sth(visible_ids)
      definition('stop-the-hate-quarterly', 'Reports::Youth::StopTheHateQuarterly',
                 presets: %i[sfy_quarter custom])
        .build(clients: Client.where(id: victim.id), period: quarter,
               visible_custom_field_ids: visible_ids)
    end

    it 'renders all 7 bias categories (zeros included) for a cleared viewer' do
      report = build_sth(Set[form.id])
      incidents = report.sections.find { |s| s.key == :incidents }
      expect(incidents.restricted_hidden?).to be(false)
      expect(incidents.rows.size).to eq(7)
      expect(incidents.rows).to include(['National origin', 1])
      expect(incidents.rows).to include(['Religion', 0])
      services = report.sections.find { |s| s.key == :services }
      expect(services.rows).to include(['Navigation / Case Mgmt / Referral', 1, 1])
    end

    it 'hides the whole bias section (no values in CSV either) without clearance' do
      report = build_sth(Set.new)
      incidents = report.sections.find { |s| s.key == :incidents }
      expect(incidents.restricted_hidden?).to be(true)
      expect(incidents.rows).to be_empty
      csv = report.to_csv
      expect(csv).to include(I18n.t('reports.show.restricted_hidden'))
      expect(csv).not_to include('National origin')
    end
  end

  describe Reports::Youth::AcademicPartner do
    it 'pairs baseline vs current with the exact seeded labels and x100 GPA math' do
      pv = create(:program_stream, name: '¡Por Vida!')
      aeries = create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv)
      youth = create(:client, state: 'accepted')
      enrollment = create(:client_enrollment, client: youth, program_stream: pv,
                                              enrollment_date: Date.new(2026, 8, 15))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: aeries,
             entry_date: Date.new(2026, 9, 1),
             properties: YPROPS.merge('GPA (x100, e.g. 275 = 2.75)' => '250',
                                      'School-Day Attendance % (this period)' => '88',
                                      'Discipline Incidents (this period)' => '2'))
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: aeries,
             entry_date: Date.new(2026, 11, 20),
             properties: YPROPS.merge('GPA (x100, e.g. 275 = 2.75)' => '285',
                                      'School-Day Attendance % (this period)' => '93',
                                      'Discipline Incidents (this period)' => '0',
                                      'A-G On Track' => 'On track'))

      report = definition('academic-partner', 'Reports::Youth::AcademicPartner')
               .build(clients: Client.where(id: youth.id), period: term_period)
      gpra = report.sections.find { |s| s.key == :gpra }
      expect(gpra.rows).to include([I18n.t('reports.registry.academic_partner.rows.gpa_improved'), '1 of 1 (100%)'])
      expect(gpra.rows).to include([I18n.t('reports.registry.academic_partner.rows.attendance_improved'), '1 of 1 (100%)'])
      expect(gpra.rows).to include([I18n.t('reports.registry.academic_partner.rows.discipline_reduced'), '1 of 1 (100%)'])
      roster = report.sections.find { |s| s.key == :roster }
      # GPA is stored x100 but the district-facing artifact must read like a GPA
      # (adversarial-review fix — this used to print '250.0 ↑ 285.0')
      expect(roster.rows.sole[1]).to eq('2.50 ↑ 2.85')
      expect(roster.rows.sole[4]).to eq('On track')
    end
  end
end
