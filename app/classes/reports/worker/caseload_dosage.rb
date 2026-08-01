# frozen_string_literal: true

module Reports
  module Worker
    # W3 (youth flavor) — per-youth engagement: service contacts in the period by
    # tracking, plus cohort session attendance (Present entries / all session
    # entries logged for the enrollment — the honest to-date denominator until a
    # cohort calendar exists).
    class CaseloadDosage < BaseReport
      SESSION_TRACKING = 'Session Attendance'

      private

      def build_sections
        [contacts_section, cohort_section]
      end

      def contacts_section
        counts = scoped_trackings
                 .joins(:tracking)
                 .group('client_enrollments.client_id', 'trackings.name')
                 .count
        rows = @clients.map do |client|
          per_tracking = counts.select { |(cid, _n), _c| cid == client.id }
          total = per_tracking.values.sum
          detail = per_tracking.map { |(_cid, name), c| "#{name}: #{c}" }.sort.join(', ')
          [client_label(client), total, detail]
        end
        Section.new(key: :contacts, columns: cols(%w[youth contacts detail]), rows: rows)
      end

      def cohort_section
        session_enrollments = scoped_enrollments
                              .joins(program_stream: :trackings)
                              .where(trackings: { name: SESSION_TRACKING })
                              .includes(:client, :program_stream)
        rows = session_enrollments.map do |enrollment|
          entries = ClientEnrollmentTracking.where(client_enrollment_id: enrollment.id)
          total = entries.count
          present = Reports::ValueCounts.owner_ids(owner_scope: entries,
                                                   field_label: 'Attendance',
                                                   value: 'Present').size
          pct = total.zero? ? 0 : (100.0 * present / total).round
          [client_label(enrollment.client), enrollment.program_stream.name,
           present, total, "#{pct}%"]
        end
        Section.new(key: :cohorts, columns: cols(%w[youth cohort present sessions attendance_pct]),
                    rows: rows)
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.my_youth_dosage.columns.#{k}") }
      end
    end
  end
end
