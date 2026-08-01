# frozen_string_literal: true

module Reports
  module Youth
    # Stop The Hate Quarterly — the CDSS StH package on SFY quarters:
    #   * unduplicated individuals served, split by the StH service trackings
    #   * hate incidents by the 7 PC 422.55 bias categories — the Hate Incident
    #     Record form is RESTRICTED: the section renders ONLY when the viewer's
    #     visible_custom_field_ids admits the form (admin); everyone else gets
    #     the restricted_hidden notice in every format — absence, never zeros
    #   * priority-population demographics over the StH served set
    class StopTheHateQuarterly < BaseReport
      PROGRAM_NAME = 'Stop The Hate'
      INCIDENT_FORM = 'Hate Incident Record'
      BIAS_FIELD = 'Bias Category'
      BIAS_CATEGORIES = ['Race', 'Color', 'Disability', 'Religion', 'National origin',
                         'Sexual orientation', 'Gender identity'].freeze

      private

      def build_sections
        [services_section, incidents_section, demographics_section]
      end

      def sth_program
        @sth_program ||= ProgramStream.find_by(name: PROGRAM_NAME)
      end

      def sth_served
        @sth_served ||= sth_program ? served_client_ids([sth_program.id]) : []
      end

      def services_section
        rows = if sth_program
                 counts = scoped_trackings
                          .joins(:tracking)
                          .where(client_enrollments: { program_stream_id: sth_program.id })
                          .group('trackings.name', 'client_enrollments.client_id').count
                 sth_program.trackings.map do |tracking|
                   client_counts = counts.select { |(name, _cid), _c| name == tracking.name }
                   [tracking.name, client_counts.keys.map(&:last).uniq.size,
                    client_counts.values.sum]
                 end
               else
                 []
               end
        rows << [I18n.t('reports.show.total'), sth_served.size,
                 rows.sum { |r| r.last.to_i }]
        Section.new(key: :services, columns: cols(%w[service individuals occurrences]),
                    rows: rows)
      end

      def incidents_section
        form = CustomField.find_by(entity_type: 'Client', form_title: INCIDENT_FORM)
        unless form && visible_custom_field_ids.include?(form.id)
          return Section.new(key: :incidents, columns: cols(%w[bias_category incidents]),
                             rows: [], restricted_hidden: true)
        end

        candidates = CustomFieldProperty.where(custom_field_id: form.id,
                                               custom_formable_type: 'Client',
                                               custom_formable_id: client_ids)
        counts = Hash.new(0)
        DecryptedScan.each(candidates) do |_record, props|
          date = begin
            props['Incident Date'].present? ? Date.parse(props['Incident Date'].to_s) : nil
          rescue Date::Error
            nil
          end
          next unless date && period.range.cover?(date)
          Array(props[BIAS_FIELD]).each { |category| counts[category] += 1 }
        end
        rows = BIAS_CATEGORIES.map { |category| [category, counts.fetch(category, 0)] }
        Section.new(key: :incidents, columns: cols(%w[bias_category incidents]),
                    rows: rows,
                    footnote: I18n.t('reports.registry.stop_the_hate_quarterly.incident_footnote'))
      end

      def demographics_section
        rows = []
        %w[Race Ethnicity].each do |type_name|
          qt = QuantitativeType.find_by(name: type_name)
          next if qt.nil?
          qt.quantitative_cases.each do |qc|
            rows << ["#{type_name}: #{qc.value}",
                     ClientQuantitativeCase.where(quantitative_case_id: qc.id,
                                                  client_id: sth_served).count]
          end
        end
        Section.new(key: :demographics, columns: cols(%w[population individuals]),
                    rows: rows)
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.stop_the_hate_quarterly.columns.#{k}") }
      end
    end
  end
end
