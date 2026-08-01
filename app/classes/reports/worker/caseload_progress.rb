# frozen_string_literal: true

module Reports
  module Worker
    # W1 — "outcomes and progress of THEIR cases" (owner's worker-tier framing):
    # one row per client in the viewer's ability scope — active programs, last
    # service contact, assessment movement (first vs latest average over the
    # domains the VIEWER may see), plus a %-improved summary row.
    class CaseloadProgress < BaseReport
      private

      def build_sections
        rows = []
        improved = 0
        assessed = 0

        clients_in_scope.each do |client|
          first_avg, latest_avg = assessment_averages(client)
          delta = first_avg && latest_avg ? (latest_avg - first_avg).round(2) : nil
          if delta
            assessed += 1
            improved += 1 if delta.positive?
          end
          rows << [client_label(client),
                   active_programs.fetch(client.id, []).join(', '),
                   last_contact.fetch(client.id, nil) || I18n.t('reports.show.no_data'),
                   client.assessments.size,
                   first_avg || '—', latest_avg || '—', delta || '—']
        end

        summary = if assessed.positive?
                    I18n.t('reports.registry.my_caseload_progress.summary',
                           improved: improved, assessed: assessed,
                           percent: (100.0 * improved / assessed).round)
                  end

        [Section.new(key: :caseload, columns: columns, rows: rows, footnote: summary)]
      end

      def clients_in_scope
        @clients_in_scope ||= @clients.includes(:assessments).sort_by { |c| c.name.to_s }
      end

      def active_programs
        @active_programs ||= ClientEnrollment.where(client_id: client_ids, status: 'Active')
                                             .joins(:program_stream)
                                             .pluck(:client_id, 'program_streams.name')
                                             .group_by(&:first)
                                             .transform_values { |pairs| pairs.map(&:last).sort }
      end

      def last_contact
        @last_contact ||= ClientEnrollmentTracking
                          .joins(:client_enrollment)
                          .where(client_enrollments: { client_id: client_ids })
                          .group('client_enrollments.client_id')
                          .maximum(:entry_date)
      end

      # First vs latest assessment average over VISIBLE domains only (fail-closed
      # masking — the CsiStatistic posture).
      def assessment_averages(client)
        ordered = client.assessments.sort_by(&:created_at)
        return [nil, nil] if ordered.size < 2
        [avg_visible_score(ordered.first), avg_visible_score(ordered.last)]
      end

      def avg_visible_score(assessment)
        scores = AssessmentDomain.joins(:domain)
                                 .where(assessment_id: assessment.id,
                                        domains: { sensitivity: visible_domain_levels })
                                 .pluck(:score).compact
        return nil if scores.empty?
        (scores.sum.to_f / scores.size).round(2)
      end

      def columns
        %w[client programs last_contact assessments first_avg latest_avg change].map do |key|
          I18n.t("reports.registry.my_caseload_progress.columns.#{key}")
        end
      end
    end
  end
end
