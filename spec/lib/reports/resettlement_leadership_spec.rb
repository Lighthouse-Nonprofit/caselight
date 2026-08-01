# frozen_string_literal: true
require 'rails_helper'

# Reports batch R5 — resettlement leadership pack A:
#   * Demographics: age-band edges at PERIOD END, country zero rows, household
#     size buckets, quantitative distributions with zeros
#   * SelfSufficiency: matched-pair selection (single-assessment clients count
#     toward coverage only), per-domain movement, masking (restricted domains
#     invisible to a standard-only viewer)
RSpec.describe 'resettlement leadership pack A' do
  let(:period) do
    Reports::Period.new(preset: :calendar_year,
                        range: Date.new(2026, 1, 1)..Date.new(2026, 12, 31))
  end
  let(:program) { create(:program_stream, name: 'Housing') }

  def build(slug, klass, scope, **kwargs)
    Reports::Registry::Definition.new(slug: slug, klass_name: klass,
                                      audience: :leadership, presets: %i[calendar_year])
                                 .build(clients: scope, period: period, **kwargs)
  end

  describe Reports::Resettlement::Demographics do
    it 'computes age bands at period end (edge: 18th birthday ON Dec 31)' do
      country = Province.create!(name: 'Afghanistan')
      just_18 = create(:client, state: 'accepted', date_of_birth: Date.new(2008, 12, 31),
                                birth_province_id: country.id)
      still_17 = create(:client, state: 'accepted', date_of_birth: Date.new(2009, 1, 1))
      [just_18, still_17].each do |c|
        create(:client_enrollment, client: c, program_stream: program,
                                   enrollment_date: Date.new(2026, 3, 1))
      end

      report = build('demographics', 'Reports::Resettlement::Demographics',
                     Client.where(id: [just_18.id, still_17.id]))
      age_rows = report.sections.find { |s| s.key == :age_gender }.rows
      expect(age_rows).to include(['Age 18-24', 1]) # 18 exactly at period end
      expect(age_rows).to include(['Age 5-17', 1])

      country_rows = report.sections.find { |s| s.key == :country }.rows
      expect(country_rows).to include(['Afghanistan', 1])
      expect(country_rows).to include([I18n.t('reports.show.unknown'), 1])
    end
  end

  describe Reports::Resettlement::SelfSufficiency do
    let!(:standard_domain) { create(:domain, name: 'S1', identity: 'Housing Stability', sensitivity: 'standard') }
    let!(:restricted_domain) { create(:domain, name: 'R1', identity: 'Immigration Status', sensitivity: 'restricted') }
    let(:paired) { create(:client, state: 'accepted') }
    let(:single) { create(:client, state: 'accepted') }

    before do
      first = create(:assessment, client: paired, created_at: Date.new(2025, 6, 1))
      latest = create(:assessment, client: paired, created_at: Date.new(2026, 3, 1))
      create(:assessment_domain, assessment: first, domain: standard_domain, score: 2)
      create(:assessment_domain, assessment: latest, domain: standard_domain, score: 4)
      create(:assessment_domain, assessment: first, domain: restricted_domain, score: 1)
      create(:assessment_domain, assessment: latest, domain: restricted_domain, score: 3)
      create(:assessment, client: single, created_at: Date.new(2026, 2, 1))
    end

    it 'movement uses matched pairs only; coverage counts everyone assessed' do
      report = build('self-sufficiency', 'Reports::Resettlement::SelfSufficiency',
                     Client.where(id: [paired.id, single.id]),
                     visible_domain_levels: %w[standard restricted])
      movement = report.sections.find { |s| s.key == :movement }
      housing = movement.rows.find { |r| r.first == 'Housing Stability' }
      expect(housing).to eq(['Housing Stability', 1, 2.0, 4.0, '100%'])
      expect(movement.footnote).to include('2 individuals assessed')
      expect(movement.footnote).to include('1 matched')
    end

    it 'masks restricted domains for a standard-only viewer' do
      report = build('self-sufficiency', 'Reports::Resettlement::SelfSufficiency',
                     Client.where(id: [paired.id]),
                     visible_domain_levels: [SensitivityPolicy::STANDARD])
      labels = report.sections.find { |s| s.key == :movement }.rows.map(&:first)
      expect(labels).to include('Housing Stability')
      expect(labels).not_to include('Immigration Status')
    end
  end
end
