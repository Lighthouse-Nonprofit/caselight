# frozen_string_literal: true

module Reports
  module Youth
    # Youth Demographics — the disaggregation every youth funder demands (EYC
    # focus populations, StH priority populations, school partners), all over
    # PLAINTEXT quantitative joins: race (multi), ethnicity, preferred language
    # (incl. the Indigenous languages), school site, grade level, poverty
    # level — plus age bands and gender. Every enumerated value renders (zeros
    # included; a funder reads absence as unreported, not as zero).
    class Demographics < BaseReport
      QUANTITATIVE_SECTIONS = ['Race', 'Ethnicity', 'Preferred Language',
                               'School', 'Grade Level', 'Poverty Level'].freeze

      private

      def build_sections
        @served = served_client_ids
        [age_gender_section, *quantitative_sections]
      end

      def age_gender_section
        rows = []
        band_counts = Hash.new(0)
        gender_counts = Hash.new(0)
        Client.where(id: @served).pluck(:date_of_birth, :gender).each do |dob, gender|
          band_counts[age_band(dob)] += 1
          gender_counts[gender.presence || I18n.t('reports.show.unknown')] += 1
        end
        (AGE_BANDS + [I18n.t('reports.show.unknown')]).each do |band|
          next if band == I18n.t('reports.show.unknown') && band_counts[band].zero?
          rows << [I18n.t('reports.registry.demographics.age_prefix', band: band), band_counts[band]]
        end
        gender_counts.sort.each do |gender, count|
          rows << [I18n.t('reports.registry.demographics.gender_prefix', gender: gender.humanize), count]
        end
        Section.new(key: :age_gender,
                    columns: [I18n.t('reports.registry.demographics.columns.group'),
                              I18n.t('reports.registry.youth_served.columns.youth')],
                    rows: rows)
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
                      title: type_name, # dynamic section: CSV/PDF need a real title
                      columns: [type_name, I18n.t('reports.registry.youth_served.columns.youth')],
                      rows: rows)
        end
      end
    end
  end
end
