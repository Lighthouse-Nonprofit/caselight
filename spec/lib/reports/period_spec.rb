# frozen_string_literal: true
require 'rails_helper'

# Reports batch — the period resolver: every funder calendar both flavors answer
# to, frozen-clock tested (the staff-monthly-report travel_to pattern).
RSpec.describe Reports::Period do
  let(:definition) do
    Reports::Registry::Definition.new(
      slug: 'test', klass_name: 'Reports::BaseReport', audience: :leadership,
      presets: %i[ffy orr_trimester ca_sfy sfy_quarter term eyc_half calendar_year custom]
    )
  end

  around { |example| travel_to(Time.zone.local(2026, 8, 15, 10, 0)) { example.run } }

  describe '.current' do
    it 'FFY: Aug 2026 sits in FFY2026 (Oct 2025 – Sep 2026)' do
      period = described_class.current(:ffy)
      expect(period.range).to eq(Date.new(2025, 10, 1)..Date.new(2026, 9, 30))
    end

    it 'ORR trimester: Aug 2026 is T3 (Jun–Sep)' do
      period = described_class.current(:orr_trimester)
      expect(period.range).to eq(Date.new(2026, 6, 1)..Date.new(2026, 9, 30))
    end

    it 'CA SFY: Aug 2026 sits in SFY2027 (Jul 2026 – Jun 2027)' do
      period = described_class.current(:ca_sfy)
      expect(period.range).to eq(Date.new(2026, 7, 1)..Date.new(2027, 6, 30))
    end

    it 'SFY quarter: Aug 2026 is Q1 SFY2027 (Jul–Sep)' do
      period = described_class.current(:sfy_quarter)
      expect(period.range).to eq(Date.new(2026, 7, 1)..Date.new(2026, 9, 30))
      expect(period.label).to include('Q1 SFY2027')
    end

    it 'term: Aug 2026 is Fall 26 (Aug–Dec) and carries the term_label' do
      period = described_class.current(:term)
      expect(period.range).to eq(Date.new(2026, 8, 1)..Date.new(2026, 12, 31))
      expect(period.term_label).to eq('Fall 26')
    end

    it 'term gap month falls back to the most recent completed term' do
      # July sits in no school term; re-freeze (nested travel_to blocks with a
      # different time raise, so pop the around's freeze first).
      travel_back
      travel_to(Time.zone.local(2026, 7, 10, 10, 0))
      period = described_class.current(:term)
      expect(period.range).to eq(Date.new(2026, 1, 1)..Date.new(2026, 6, 30))
      expect(period.term_label).to eq('Spring 26')
    end

    it 'EYC half: Aug 2026 is Jul–Dec 2026' do
      period = described_class.current(:eyc_half)
      expect(period.range).to eq(Date.new(2026, 7, 1)..Date.new(2026, 12, 31))
    end
  end

  describe '.resolve' do
    it 'round-trips an option param and enforces the definition allowlist' do
      option = described_class.current(:ffy)
      resolved = described_class.resolve(definition, { period: option.param_value })
      expect(resolved.range).to eq(option.range)

      narrow = Reports::Registry::Definition.new(slug: 't2', klass_name: 'Reports::BaseReport',
                                                 audience: :leadership, presets: %i[term custom])
      fallback = described_class.resolve(narrow, { period: option.param_value })
      expect(fallback.preset).to eq(:term) # disallowed preset falls back to the first preset
    end

    it 'accepts a valid custom range and rejects a reversed one' do
      period = described_class.resolve(definition, { from: '2026-01-01', to: '2026-03-31' })
      expect(period.preset).to eq(:custom)
      expect(period.range).to eq(Date.new(2026, 1, 1)..Date.new(2026, 3, 31))

      fallback = described_class.resolve(definition, { from: '2026-03-31', to: '2026-01-01' })
      expect(fallback.preset).to eq(:ffy) # falls back to the first preset
    end

    it 'survives garbage params (falls back to the first preset)' do
      period = described_class.resolve(definition, { period: 'lol|nope|what', from: 'x', to: 'y' })
      expect(period.preset).to eq(:ffy)
    end
  end

  it 'options_for lists recent instances newest-first per preset, no custom entry' do
    options = described_class.options_for(definition)
    expect(options.map(&:preset)).not_to include(:custom)
    ffy_options = options.select { |o| o.preset == :ffy }
    expect(ffy_options.size).to eq(3)
    expect(ffy_options.first.range.begin).to be > ffy_options.last.range.begin
  end
end
