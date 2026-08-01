# frozen_string_literal: true

module Reports
  module Youth
    # Enrollment & Dosage — the EYC/StH engagement shape per program: enrolled
    # in period, distinct youth served, service contacts by tracking type, mean
    # contacts per youth, and — for cohort programs — % of enrolled youth at or
    # above the completer threshold (75% of logged sessions attended).
    class EnrollmentDosage < BaseReport
      SESSION_TRACKING = 'Session Attendance'
      COMPLETER_THRESHOLD = 0.75

      private

      def build_sections
        [dosage_section]
      end

      def dosage_section
        rows = ProgramStream.order(:name).map do |program|
          served = served_client_ids([program.id])
          units_by_tracking = scoped_trackings
                              .joins(:tracking)
                              .where(client_enrollments: { program_stream_id: program.id })
                              .group('trackings.name').count
          total_units = units_by_tracking.values.sum
          mean = served.empty? ? 0 : (total_units.to_f / served.size).round(1)
          detail = units_by_tracking.sort.map { |name, count| "#{name}: #{count}" }.join(', ')
          [program.name, served.size, total_units, mean, detail, completer_cell(program)]
        end

        Section.new(key: :dosage, columns: cols,
                    rows: rows,
                    footnote: I18n.t('reports.registry.enrollment_dosage.footnote'))
      end

      # % of the program's enrollments at >= 75% Present across their logged
      # session entries; '—' for non-cohort programs (no Session Attendance).
      def completer_cell(program)
        session_tracking = program.trackings.find_by(name: SESSION_TRACKING)
        return '—' if session_tracking.nil?

        enrollments = scoped_enrollments([program.id])
        return '0%' if enrollments.none?

        completers = enrollments.count do |enrollment|
          entries = ClientEnrollmentTracking.where(client_enrollment_id: enrollment.id,
                                                   tracking_id: session_tracking.id)
          total = entries.count
          next false if total.zero?
          present = Reports::ValueCounts.owner_ids(owner_scope: entries,
                                                   field_label: 'Attendance',
                                                   value: 'Present').size
          present.to_f / total >= COMPLETER_THRESHOLD
        end
        "#{(100.0 * completers / enrollments.size).round}%"
      end

      def cols
        %w[program youth service_units mean_contacts detail completers].map do |key|
          I18n.t("reports.registry.enrollment_dosage.columns.#{key}")
        end
      end
    end
  end
end
