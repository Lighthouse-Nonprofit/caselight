# frozen_string_literal: true

module Reports
  module Resettlement
    # Service Activity — service units (tracking entries on their SERVICE date)
    # by month × program, as a line chart + table, plus a contacts-per-active-
    # household rate. Months are bucketed in the app time zone.
    class ServiceActivity < BaseReport
      private

      def build_sections
        [monthly_section, rate_section]
      end

      def monthly_section
        months = month_starts
        programs = ProgramStream.order(:name).to_a
        counts = scoped_trackings
                 .joins(client_enrollment: :program_stream)
                 .group("date_trunc('month', entry_date)", 'program_streams.name')
                 .count
                 .transform_keys { |(month, name)| [month.to_date, name] }

        labels = months.map { |m| m.strftime('%b %y') }
        series = programs.map do |program|
          { name: program.name,
            data: months.map { |m| counts.fetch([m, program.name], 0) } }
        end

        rows = programs.map do |program|
          [program.name, *months.map { |m| counts.fetch([m, program.name], 0) }]
        end

        Section.new(
          key: :monthly,
          columns: [I18n.t('reports.registry.service_activity.columns.program'), *labels],
          rows: rows,
          chart: { type: :line, data: [labels, series] }
        )
      end

      def rate_section
        # households active DURING THE PERIOD, not whatever is Active today —
        # otherwise a past-year report divides its units by today's caseload.
        active_ids = scoped_enrollments
                     .where(enrollment_date: ..period.end_date)
                     .left_joins(:leave_program)
                     .where('leave_programs.id IS NULL OR leave_programs.exit_date >= ?', period.start_date)
                     .pluck(:client_id).uniq
        households = household_count(active_ids)
        units = scoped_trackings.count
        rate = households.zero? ? 0 : (units.to_f / households).round(1)
        rows = [[I18n.t('reports.registry.service_activity.contacts_per_household'),
                 units, households, rate]]
        Section.new(key: :rate,
                    columns: %w[metric service_units households rate].map { |k| I18n.t("reports.registry.service_activity.columns.#{k}") },
                    rows: rows)
      end

      def month_starts
        first = period.start_date.beginning_of_month
        last = period.end_date.beginning_of_month
        months = []
        cursor = first
        while cursor <= last
          months << cursor
          cursor = cursor.next_month
        end
        months
      end
    end
  end
end
