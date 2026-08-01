# frozen_string_literal: true
require 'rails_helper'

# Reports batch R8 — FunderAttribution v1 (Agencies ≡ funders via their program
# mappings) + the flavor-correct landing chart:
#   * unmapped agencies excluded; mapped agencies with zero activity still render
#   * unduplication across an agency's multiple programs
#   * overlap buckets (covered by 1 / 2 / 3+ funders)
#   * EnrollmentStatistic: 12-month active-enrollment series from program names
RSpec.describe 'funder attribution + landing chart' do
  let(:period) do
    Reports::Period.new(preset: :calendar_year,
                        range: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
  end
  let(:pv) { create(:program_stream, name: '¡Por Vida!') }
  let(:sth) { create(:program_stream, name: 'Stop The Hate') }

  describe Reports::FunderAttribution do
    it 'attributes unduplicated clients per funder and buckets the overlap' do
      dhcs = create(:agency, name: 'Elevate Youth CA')
      cdss = create(:agency, name: 'CDSS Stop the Hate')
      create(:agency, name: 'Unmapped Foundation')
      AgencyProgramStream.create!(agency: dhcs, program_stream: pv)
      AgencyProgramStream.create!(agency: dhcs, program_stream: sth)
      AgencyProgramStream.create!(agency: cdss, program_stream: sth)

      both = create(:client, state: 'accepted')   # PV + STH -> covered by both funders
      pv_only = create(:client, state: 'accepted')
      create(:client_enrollment, client: both, program_stream: pv, enrollment_date: Date.new(2026, 2, 1))
      create(:client_enrollment, client: both, program_stream: sth, enrollment_date: Date.new(2026, 3, 1))
      create(:client_enrollment, client: pv_only, program_stream: pv, enrollment_date: Date.new(2026, 4, 1))

      report = Reports::Registry::Definition.new(slug: 'funder-attribution',
                                                 klass_name: 'Reports::FunderAttribution',
                                                 audience: :leadership, presets: %i[calendar_year])
                                            .build(clients: Client.where(id: [both.id, pv_only.id]),
                                                   period: period)
      attribution = report.sections.find { |s| s.key == :attribution }
      expect(attribution.rows.map(&:first)).to contain_exactly('Elevate Youth CA', 'CDSS Stop the Hate')
      dhcs_row = attribution.rows.find { |r| r.first == 'Elevate Youth CA' }
      expect(dhcs_row[2]).to eq(2) # both + pv_only, unduplicated across PV/STH

      overlap = report.sections.find { |s| s.key == :overlap }
      one = overlap.rows.find { |r| r.first == I18n.t('reports.registry.funder_attribution.covered_by', count: '1') }
      two = overlap.rows.find { |r| r.first == I18n.t('reports.registry.funder_attribution.covered_by', count: '2') }
      expect(one.last).to eq(1) # pv_only
      expect(two.last).to eq(1) # both
    end
  end

  describe Reports::EnrollmentStatistic do
    it 'builds a 12-month active series per program' do
      client = create(:client, state: 'accepted')
      enrollment = create(:client_enrollment, client: client, program_stream: pv,
                                              enrollment_date: 3.months.ago.to_date)
      LeaveProgram.create!(client_enrollment_id: enrollment.id, program_stream_id: pv.id,
                           exit_date: 1.month.ago.to_date, properties: {})

      labels, series = described_class.new(Client.where(id: client.id)).statistic_data
      expect(labels.size).to eq(12)
      pv_series = series.find { |s| s[:name] == '¡Por Vida!' }
      expect(pv_series[:data].size).to eq(12)
      expect(pv_series[:data][8]).to eq(1)  # ~3 months ago: active
      expect(pv_series[:data].last).to eq(0) # current month: exited
    end
  end
end
