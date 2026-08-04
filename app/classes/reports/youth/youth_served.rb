# frozen_string_literal: true

module Reports
  module Youth
    # Unduplicated Youth Served — per program, plus by school site and
    # new-vs-returning. "New" = the youth's first-ever service contact falls in
    # the period (VOCA PMT convention). School-site breakdown rides the PLAINTEXT
    # quantitative join. Zero rows render for every program and every seeded site.
    class YouthServed < BaseReport
      private

      def build_sections
        [program_section, site_section, new_returning_section]
      end

      def program_section
        rows = ProgramStream.order(:name).map do |program|
          ids = served_client_ids([program.id])
          units = scoped_trackings
                  .where(client_enrollments: { program_stream_id: program.id }).count
          [program.name, ids.size, units]
        end
        all_ids = served_client_ids
        rows << [I18n.t('reports.show.total'), all_ids.size, scoped_trackings.count]
        Section.new(
          key: :by_program,
          columns: registry_columns(%w[program youth service_units]),
          rows: rows
        )
      end

      def site_section
        site_type = QuantitativeType.find_by(name: 'School Site')
        return Section.new(key: :by_site, columns: registry_columns(%w[site youth]), rows: []) if site_type.nil?

        served = served_client_ids
        rows = site_type.quantitative_cases.map do |qc|
          count = ClientQuantitativeCase.where(quantitative_case_id: qc.id,
                                               client_id: served).count
          [qc.value, count]
        end
        Section.new(key: :by_site, columns: registry_columns(%w[site youth]), rows: rows)
      end

      def new_returning_section
        served = served_client_ids
        return Section.new(key: :new_returning,
                           columns: registry_columns(%w[category youth]),
                           rows: [[I18n.t('reports.registry.youth_served.new_label'), 0],
                                  [I18n.t('reports.registry.youth_served.returning_label'), 0]]) if served.empty?

        # NEW = no service history before this period (VOCA convention: served
        # for the first time ever). A youth enrolled this period who has no
        # logged contact yet is still NEW — never silently "returning".
        prior_contact_ids = ClientEnrollmentTracking
                            .joins(:client_enrollment)
                            .where(client_enrollments: { client_id: served })
                            .where(entry_date: ...period.start_date)
                            .distinct.pluck('client_enrollments.client_id')
        new_ids = served - prior_contact_ids
        Section.new(
          key: :new_returning,
          columns: registry_columns(%w[category youth]),
          rows: [[I18n.t('reports.registry.youth_served.new_label'), new_ids.size],
                 [I18n.t('reports.registry.youth_served.returning_label'), served.size - new_ids.size]]
        )
      end

      def registry_columns(keys)
        keys.map { |k| I18n.t("reports.registry.youth_served.columns.#{k}") }
      end
    end
  end
end
