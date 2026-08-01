# frozen_string_literal: true

module Reports
  module Youth
    # Academic Partner Report — the ¡Por Vida! deliverable to the school
    # district, phrased in GPRA/CA-dashboard vocabulary: per youth with Aeries
    # check-ins in the period window, baseline (first check-in in the
    # enrollment) vs current (latest on/before period end) for GPA, attendance,
    # credits, A-G, discipline — and the GPRA improvement counts among the
    # <3.0-GPA and <=90%-attendance baseline cohorts. Aeries fields are
    # encrypted properties -> bounded DecryptedScan.
    class AcademicPartner < BaseReport
      PROGRAM_NAME = '¡Por Vida!'
      TRACKING_NAME = 'Academic Check-in (Aeries)'
      # Field labels EXACTLY as youth_taxonomy.rake seeds them (properties are
      # label-keyed); GPA is stored x100, so the GPRA <3.0 baseline = 300.
      GPA_FIELD = 'GPA (x100, e.g. 275 = 2.75)'
      CREDITS_FIELD = 'Credits Earned (cumulative)'
      AG_FIELD = 'A-G On Track'
      ATTENDANCE_FIELD = 'School-Day Attendance % (this period)'
      DISCIPLINE_FIELD = 'Discipline Incidents (this period)'
      GPRA_GPA_BASELINE = 300
      GPRA_ATTENDANCE_BASELINE = 90.0

      private

      def build_sections
        pairs = baseline_current_pairs
        [roster_section(pairs), gpra_section(pairs)]
      end

      def roster_section(pairs)
        rows = pairs.map do |pair|
          [client_label(pair[:client]),
           format_delta(pair, GPA_FIELD),
           format_delta(pair, ATTENDANCE_FIELD),
           format_delta(pair, CREDITS_FIELD),
           pair[:current][AG_FIELD].presence || '—',
           format_delta(pair, DISCIPLINE_FIELD)]
        end
        Section.new(key: :roster, columns: cols(%w[youth gpa attendance credits a_g discipline]),
                    rows: rows)
      end

      def gpra_section(pairs)
        gpa_cohort = pairs.select { |p| numeric(p[:baseline][GPA_FIELD])&.< GPRA_GPA_BASELINE }
        gpa_improved = gpa_cohort.count { |p| improved?(p, GPA_FIELD) }
        att_cohort = pairs.select { |p| numeric(p[:baseline][ATTENDANCE_FIELD])&.<= GPRA_ATTENDANCE_BASELINE }
        att_improved = att_cohort.count { |p| improved?(p, ATTENDANCE_FIELD) }
        disc_cohort = pairs.select { |p| (numeric(p[:baseline][DISCIPLINE_FIELD]) || 0).positive? }
        disc_reduced = disc_cohort.count do |p|
          base = numeric(p[:baseline][DISCIPLINE_FIELD])
          cur = numeric(p[:current][DISCIPLINE_FIELD])
          base && cur && cur < base
        end

        rows = [
          [I18n.t('reports.registry.academic_partner.rows.gpa_improved'), pct_row(gpa_improved, gpa_cohort.size)],
          [I18n.t('reports.registry.academic_partner.rows.attendance_improved'), pct_row(att_improved, att_cohort.size)],
          [I18n.t('reports.registry.academic_partner.rows.discipline_reduced'), pct_row(disc_reduced, disc_cohort.size)]
        ]
        Section.new(key: :gpra, columns: cols(%w[measure result]), rows: rows,
                    footnote: I18n.t('reports.registry.academic_partner.footnote'))
      end

      # One pair per youth: first check-in (baseline) + latest on/before period
      # end (current), keeping only youths whose latest check-in falls in period.
      def baseline_current_pairs
        @pairs ||= begin
          program = ProgramStream.find_by(name: PROGRAM_NAME)
          return [] if program.nil?
          tracking = program.trackings.find_by(name: TRACKING_NAME)
          return [] if tracking.nil?

          entries = ClientEnrollmentTracking
                    .joins(client_enrollment: :client)
                    .where(tracking_id: tracking.id, entry_date: ..period.end_date,
                           client_enrollments: { client_id: client_ids })
                    .includes(client_enrollment: :client)
                    .order(:entry_date, :created_at)
          by_client = Hash.new { |h, k| h[k] = [] }
          DecryptedScan.each(entries) do |record, props|
            by_client[record.client_enrollment.client] << { date: record.entry_date, props: props }
          end
          by_client.filter_map do |client, list|
            next unless period.range.cover?(list.last[:date])
            { client: client, baseline: list.first[:props], current: list.last[:props] }
          end
        end
      end

      def numeric(value)
        return nil if value.blank?
        Float(value)
      rescue ArgumentError, TypeError
        nil
      end

      def improved?(pair, field)
        base = numeric(pair[:baseline][field])
        cur = numeric(pair[:current][field])
        base && cur && cur > base
      end

      def format_delta(pair, field)
        base = numeric(pair[:baseline][field])
        cur = numeric(pair[:current][field])
        return '—' if cur.nil?
        return cur.to_s if base.nil? || base == cur
        arrow = cur > base ? '↑' : '↓'
        "#{base} #{arrow} #{cur}"
      end

      def pct_row(numerator, denominator)
        return I18n.t('reports.show.no_data') if denominator.zero?
        "#{numerator} of #{denominator} (#{(100.0 * numerator / denominator).round}%)"
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.academic_partner.columns.#{k}") }
      end
    end
  end
end
