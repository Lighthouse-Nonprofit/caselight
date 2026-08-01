# frozen_string_literal: true

module Reports
  module Resettlement
    # Demographics Profile — the disaggregation every funder demands, computed
    # over the SERVED set for the period, all on PLAINTEXT surfaces: country of
    # origin (birth_province FK — the provinces table carries the seeded
    # countries list), age bands at period end (AOGP bands), gender, household
    # size, and the seeded quantitative lists (every enumerated value renders,
    # zeros included).
    class Demographics < BaseReport
      QUANTITATIVE_SECTIONS = ['English Proficiency', 'Monthly Household Income Range',
                               'Public Benefits Enrolled'].freeze

      private

      def build_sections
        @served = served_client_ids
        [country_section, age_gender_section, household_size_section,
         *quantitative_sections]
      end

      def country_section
        counts = Client.where(id: @served)
                       .left_joins(:birth_province)
                       .group('provinces.name').count
        rows = Province.order(:name).map { |p| [p.name, counts.fetch(p.name, 0)] }
        unknown = counts.fetch(nil, 0)
        rows << [I18n.t('reports.show.unknown'), unknown]
        Section.new(key: :country, columns: cols(%w[country individuals]),
                    rows: rows)
      end

      def age_gender_section
        dobs = Client.where(id: @served).pluck(:id, :date_of_birth, :gender)
        band_counts = Hash.new(0)
        gender_counts = Hash.new(0)
        dobs.each do |_id, dob, gender|
          band_counts[age_band(dob)] += 1
          gender_counts[gender.presence || I18n.t('reports.show.unknown')] += 1
        end
        rows = (AGE_BANDS + [I18n.t('reports.show.unknown')]).filter_map do |band|
          next if band == I18n.t('reports.show.unknown') && band_counts[band].zero?
          [I18n.t('reports.registry.demographics.age_prefix', band: band), band_counts[band]]
        end
        rows += gender_counts.sort.map { |g, c| [I18n.t('reports.registry.demographics.gender_prefix', gender: g.humanize), c] }
        Section.new(key: :age_gender, columns: cols(%w[group individuals]), rows: rows)
      end

      def household_size_section
        family_ids = Case.where(client_id: @served, case_type: 'KC').distinct.pluck(:family_id)
        sizes = Family.where(id: family_ids).map { |f| f.cases.count }
        solo = (@served - Case.where(client_id: @served, case_type: 'KC').distinct.pluck(:client_id)).size
        buckets = Hash.new(0)
        sizes.each do |size|
          key = size >= 6 ? '6+' : size.to_s
          buckets[key] += 1
        end
        buckets['1'] += solo
        rows = (%w[1 2 3 4 5 6+]).map { |k| [k, buckets.fetch(k, 0)] }
        Section.new(key: :household_size, columns: cols(%w[household_size households]), rows: rows)
      end

      def quantitative_sections
        QUANTITATIVE_SECTIONS.filter_map do |type_name|
          qt = QuantitativeType.find_by(name: type_name)
          next if qt.nil?
          rows = qt.quantitative_cases.map do |qc|
            [qc.value, ClientQuantitativeCase.where(quantitative_case_id: qc.id,
                                                    client_id: @served).count]
          end
          Section.new(key: :"quant_#{type_name.parameterize.underscore}",
                      columns: [type_name, I18n.t('reports.registry.demographics.columns.individuals')],
                      rows: rows)
        end
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.demographics.columns.#{k}") }
      end
    end
  end
end
