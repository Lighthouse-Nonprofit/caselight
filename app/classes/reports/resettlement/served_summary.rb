# frozen_string_literal: true

module Reports
  module Resettlement
    # Unduplicated Served Summary — the first line of every funder report:
    # unduplicated individuals AND households per program, PAIRED with the
    # duplicated service-unit count ("clients" vs "services", the ORR/WA-ORIA
    # counting legend). Total row de-duplicates across programs. Zero-enrollment
    # programs still render (funders require reported zeros).
    class ServedSummary < BaseReport
      private

      def build_sections
        rows = ProgramStream.order(:name).map do |program|
          ids = served_client_ids([program.id])
          units = scoped_trackings
                  .where(client_enrollments: { program_stream_id: program.id }).count
          [program.name, ids.size, household_count(ids), units]
        end
        all_ids = served_client_ids
        total_units = scoped_trackings.count
        rows << [I18n.t('reports.show.total'), all_ids.size, household_count(all_ids), total_units]

        [Section.new(
          key: :served,
          columns: [
            I18n.t('reports.registry.served_summary.columns.program'),
            I18n.t('reports.registry.served_summary.columns.individuals'),
            I18n.t('reports.registry.served_summary.columns.households'),
            I18n.t('reports.registry.served_summary.columns.service_units')
          ],
          rows: rows,
          footnote: I18n.t('reports.registry.served_summary.footnote')
        )]
      end
    end
  end
end
