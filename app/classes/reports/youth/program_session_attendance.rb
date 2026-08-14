# frozen_string_literal: true

module Reports
  module Youth
    # Program session attendance — org-wide roll-call attendance across every program that
    # carries a Session Attendance tracking (the cultura curricula + the youth councils):
    # Present / Absent / Excused counts and the attendance rate per program, plus a total.
    # Leadership-tier, the funder-facing companion to the per-cohort Cohort Completion.
    # Attendance is an encrypted tracking property counted via the indexed ValueCounts path.
    class ProgramSessionAttendance < BaseReport
      SESSION_TRACKING = Cohorts::SESSION_TRACKING
      ATTENDANCE_FIELD = 'Attendance'
      STATUSES = %w[Present Absent Excused].freeze

      private

      def build_sections
        rows = []
        totals = Hash.new(0)
        session_programs.each do |program|
          counts = status_counts(program)
          logged = STATUSES.sum { |s| counts[s] }
          STATUSES.each { |s| totals[s] += counts[s] }
          rows << [program.name, logged, counts['Present'], counts['Absent'], counts['Excused'],
                   rate(counts['Present'], logged)]
        end
        unless rows.empty?
          grand = STATUSES.sum { |s| totals[s] }
          rows << [t(:total_row), grand, totals['Present'], totals['Absent'], totals['Excused'],
                   rate(totals['Present'], grand)]
        end
        [Section.new(key: :attendance, columns: cols, rows: rows, footnote: t(:footnote))]
      end

      def session_programs
        ProgramStream.joins(:trackings)
                     .where(trackings: { name: SESSION_TRACKING })
                     .order(:name).distinct
      end

      # { 'Present' => n, 'Absent' => n, 'Excused' => n } within the period, ability-scoped.
      def status_counts(program)
        tracking = program.trackings.find_by(name: SESSION_TRACKING)
        return Hash.new(0) if tracking.nil?
        entries = scoped_trackings.where(tracking_id: tracking.id)
        STATUSES.index_with do |status|
          Reports::ValueCounts.owner_ids(owner_scope: entries,
                                         field_label: ATTENDANCE_FIELD, value: status).size
        end
      end

      def rate(present, logged)
        return '—' if logged.zero?
        "#{(100.0 * present / logged).round}%"
      end

      def cols
        %w[program logged present absent excused rate].map { |k| t("columns.#{k}") }
      end

      def t(key)
        I18n.t("reports.registry.program_session_attendance.#{key}")
      end
    end
  end
end
