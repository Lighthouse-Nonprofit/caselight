# frozen_string_literal: true

module Reports
  module Youth
    # School attendance — school-day attendance from the ¡Por Vida! Academic Check-in
    # (Aeries). Each youth's LATEST school-day attendance % on/before the period end: a
    # roster with a chronic-absence flag, plus a summary (average, chronically absent
    # < 90%, strong attendance >= 95%). Attendance is an encrypted tracking property, so
    # values come through the bounded DecryptedScan. Leadership-tier.
    class SchoolAttendance < BaseReport
      PROGRAM_NAME = '¡Por Vida!'
      TRACKING_NAME = 'Academic Check-in (Aeries)'
      # Label EXACTLY as youth_taxonomy.rake seeds it (properties are label-keyed).
      ATTENDANCE_FIELD = 'School-Day Attendance % (this period)'
      CHRONIC_THRESHOLD = 90.0
      STRONG_THRESHOLD = 95.0

      private

      def build_sections
        latest = latest_attendance
        [roster_section(latest), summary_section(latest)]
      end

      def roster_section(latest)
        rows = latest.map do |client, pct|
          [client_label(client),
           pct.nil? ? '—' : "#{format_pct(pct)}%",
           (pct && pct < CHRONIC_THRESHOLD) ? t(:chronic_flag) : '']
        end
        Section.new(key: :roster, columns: cols(%w[youth attendance chronic]), rows: rows)
      end

      def summary_section(latest)
        vals = latest.values.compact
        avg = vals.empty? ? nil : vals.sum / vals.size
        chronic = vals.count { |v| v < CHRONIC_THRESHOLD }
        strong = vals.count { |v| v >= STRONG_THRESHOLD }
        rows = [
          [t('rows.youth_with_data'), vals.size.to_s],
          [t('rows.average'), avg.nil? ? I18n.t('reports.show.no_data') : "#{format_pct(avg)}%"],
          [t('rows.chronic'), pct_row(chronic, vals.size)],
          [t('rows.strong'), pct_row(strong, vals.size)]
        ]
        Section.new(key: :summary, columns: cols(%w[measure result]), rows: rows, footnote: t(:footnote))
      end

      # { client => latest attendance % (Float or nil) } for youths with a check-in in period.
      def latest_attendance
        program = ProgramStream.find_by(name: PROGRAM_NAME)
        tracking = program&.trackings&.find_by(name: TRACKING_NAME)
        return {} if tracking.nil?
        entries = scoped_trackings.where(tracking_id: tracking.id)
                                  .includes(client_enrollment: :client)
                                  .order(:entry_date, :created_at)
        by_client = {}
        DecryptedScan.each(entries) do |record, props|
          client = record.client_enrollment.client
          date = record.entry_date
          if by_client[client].nil? || date >= by_client[client][:date]
            by_client[client] = { date: date, pct: numeric(props[ATTENDANCE_FIELD]) }
          end
        end
        by_client.transform_values { |h| h[:pct] }
      end

      def numeric(value)
        return nil if value.blank?
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def format_pct(value)
        value == value.to_i ? value.to_i : format('%.1f', value)
      end

      def pct_row(numerator, denominator)
        return I18n.t('reports.show.no_data') if denominator.zero?
        "#{numerator} of #{denominator} (#{(100.0 * numerator / denominator).round}%)"
      end

      def cols(keys)
        keys.map { |k| t("columns.#{k}") }
      end

      def t(key)
        I18n.t("reports.registry.school_attendance.#{key}")
      end
    end
  end
end
