# frozen_string_literal: true

module Reports
  module Resettlement
    # Employment Outcomes — the AOGP definitions verbatim (the most standardized
    # metric set in refugee services):
    #   * entered employment: a client's FIRST Employed entry (placement date =
    #     'Job Start Date' when present, else the entry's service date) falling
    #     in the period; FT = explicit 'Employment Type' full-time, fallback
    #     'Hours per Week' >= 35; PT otherwise
    #   * average hourly wage over FT placements
    #   * health benefits OFFERED (regardless of uptake) as % of placements
    #   * 90-day retention: ANY subsequent Employed entry on/after day 90
    #     (any job counts — AOGP rule); denominator = placements whose day-90
    #     falls inside the period
    # Employment tracking properties are encrypted -> bounded DecryptedScan over
    # the period-narrowed candidates.
    class EmploymentOutcomes < BaseReport
      FT_THRESHOLD_HOURS = 35
      TRACKING_NAME = 'Employment Progress'
      PROGRAM_NAME = 'Employment'

      private

      def build_sections
        placements = compute_placements
        in_period = placements.select { |p| period.range.cover?(p[:date]) }
        ft = in_period.select { |p| p[:full_time] }
        pt = in_period.reject { |p| p[:full_time] }
        wages = ft.filter_map { |p| p[:wage] }
        benefits = in_period.count { |p| p[:benefits] == 'Yes' }

        retention_due = placements.select { |p| period.range.cover?(p[:date] + 90) }
        retained = retention_due.count { |p| retained?(p) }

        rows = [
          [t_row(:entered_employment), in_period.size],
          [t_row(:full_time), ft.size],
          [t_row(:part_time), pt.size],
          [t_row(:avg_wage_ft), wages.empty? ? '—' : "$#{(wages.sum / wages.size).round(2)}"],
          [t_row(:benefits_offered), in_period.empty? ? '—' : "#{benefits} (#{(100.0 * benefits / in_period.size).round}%)"],
          [t_row(:retention_denominator), retention_due.size],
          [t_row(:retention_90), retention_due.empty? ? '—' : "#{retained} (#{(100.0 * retained / retention_due.size).round}%)"]
        ]

        [Section.new(key: :outcomes, columns: cols, rows: rows,
                     footnote: I18n.t('reports.registry.employment_outcomes.footnote'))]
      end

      # One placement per client: the FIRST Employed entry ever (scan is bounded
      # to entries on/before period end so later periods stay honest).
      def compute_placements
        @placements ||= begin
          candidates = employment_entries.where(entry_date: ..period.end_date)
                                         .includes(:client_enrollment)
                                         .order(:entry_date, :created_at)
          first_by_client = {}
          DecryptedScan.each(candidates) do |record, props|
            next unless props['Status'] == 'Employed'
            client_id = record.client_enrollment.client_id
            next if first_by_client.key?(client_id)
            first_by_client[client_id] = placement_from(record, props, client_id)
          end
          first_by_client.values
        end
      end

      def placement_from(record, props, client_id)
        start = begin
          props['Job Start Date'].present? ? Date.parse(props['Job Start Date'].to_s) : record.entry_date
        rescue Date::Error
          record.entry_date
        end
        hours = props['Hours per Week'].to_s.to_f
        full_time = if props['Employment Type'].to_s.include?('Full-time')
                      true
                    elsif props['Employment Type'].to_s.include?('Part-time')
                      false
                    else
                      hours >= FT_THRESHOLD_HOURS
                    end
        { client_id: client_id, date: start, full_time: full_time,
          wage: (props['Hourly Wage (USD)'].presence&.to_f),
          benefits: props['Health Benefits Offered'].to_s }
      end

      # Retained: any Employed entry on/after placement day 90 (any job).
      def retained?(placement)
        later = employment_entries
                .joins(:client_enrollment)
                .where(client_enrollments: { client_id: placement[:client_id] })
                .where(entry_date: (placement[:date] + 90)..)
        DecryptedScan.each(later).any? { |_r, props| props['Status'] == 'Employed' }
      end

      def employment_entries
        program = ProgramStream.find_by(name: PROGRAM_NAME)
        return ClientEnrollmentTracking.none if program.nil?
        tracking = program.trackings.find_by(name: TRACKING_NAME)
        return ClientEnrollmentTracking.none if tracking.nil?
        ClientEnrollmentTracking
          .joins(:client_enrollment)
          .where(tracking_id: tracking.id,
                 client_enrollments: { client_id: client_ids })
      end

      def t_row(key) = I18n.t("reports.registry.employment_outcomes.rows.#{key}")

      def cols
        %w[metric value].map { |k| I18n.t("reports.registry.employment_outcomes.columns.#{k}") }
      end
    end
  end
end
