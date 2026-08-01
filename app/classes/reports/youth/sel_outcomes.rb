# frozen_string_literal: true

module Reports
  module Youth
    # SEL Pre/Post Outcomes — the CASEL/DESSA reporting convention: outcome math
    # over MATCHED PAIRS ONLY (first assessment = pre, latest on/before period
    # end = post); unmatched assessments count toward coverage, never outcomes.
    # Per visible domain: pairs, mean change, % improving. Masking applies
    # exactly as everywhere else (fail-closed to standard).
    class SelOutcomes < BaseReport
      private

      def build_sections
        [coverage_section, movement_section]
      end

      def coverage_section
        assessed = assessments_by_client.size
        pairs = matched_pairs.size
        rows = [
          [I18n.t('reports.registry.sel_outcomes.rows.youth_in_scope'), client_ids.size],
          [I18n.t('reports.registry.sel_outcomes.rows.assessed'), assessed],
          [I18n.t('reports.registry.sel_outcomes.rows.matched_pairs'), pairs]
        ]
        Section.new(key: :coverage,
                    columns: [I18n.t('reports.registry.sel_outcomes.columns.metric'),
                              I18n.t('reports.registry.sel_outcomes.columns.value')],
                    rows: rows)
      end

      def movement_section
        rows = Domain.where(sensitivity: visible_domain_levels).map do |domain|
          pres = []
          posts = []
          matched_pairs.each do |(pre, post)|
            pre_score = scores_index.dig(pre.id, domain.id)
            post_score = scores_index.dig(post.id, domain.id)
            next if pre_score.nil? || post_score.nil?
            pres << pre_score
            posts << post_score
          end
          n = pres.size
          improved = pres.zip(posts).count { |a, b| b > a }
          mean_change = n.zero? ? '—' : ((posts.sum - pres.sum).to_f / n).round(2)
          [domain.identity.presence || domain.name, n, mean_change,
           n.zero? ? '—' : "#{(100.0 * improved / n).round}%"]
        end
        Section.new(key: :movement,
                    columns: %w[competency pairs mean_change improving].map { |k| I18n.t("reports.registry.sel_outcomes.columns.#{k}") },
                    rows: rows,
                    footnote: I18n.t('reports.registry.sel_outcomes.footnote'))
      end

      def assessments_by_client
        @assessments_by_client ||= Assessment.where(client_id: client_ids)
                                             .where(created_at: ..period.end_date.end_of_day)
                                             .order(:created_at)
                                             .group_by(&:client_id)
      end

      def matched_pairs
        @matched_pairs ||= assessments_by_client.values
                                                .filter_map { |list| [list.first, list.last] if list.size >= 2 }
      end

      def scores_index
        @scores_index ||= AssessmentDomain
                          .where(assessment_id: matched_pairs.flatten.map(&:id))
                          .pluck(:assessment_id, :domain_id, :score)
                          .each_with_object({}) do |(aid, did, score), index|
          (index[aid] ||= {})[did] = score
        end
      end
    end
  end
end
