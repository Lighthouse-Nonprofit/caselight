# frozen_string_literal: true

module Reports
  module Resettlement
    # Self-Sufficiency Progress — the org's 12-domain 1-4 instrument as its
    # headline outcome (the Self-Sufficiency Matrix tradition): matched pairs
    # only (first assessment vs latest on/before period end), per domain the
    # VIEWER may see; plus the current income/benefits distributions
    # (point-in-time — the quantitative lists carry no history).
    class SelfSufficiency < BaseReport
      private

      def build_sections
        [domain_movement_section, *distribution_sections]
      end

      def domain_movement_section
        pairs = matched_pairs
        rows = Domain.where(sensitivity: visible_domain_levels).map do |domain|
          pres = []
          posts = []
          pairs.each do |(first, latest)|
            pre = score_for(first, domain.id)
            post = score_for(latest, domain.id)
            next if pre.nil? || post.nil?
            pres << pre
            posts << post
          end
          n = pres.size
          improved = pres.zip(posts).count { |pre, post| post > pre }
          [domain_label(domain), n,
           n.zero? ? '—' : (pres.sum.to_f / n).round(2),
           n.zero? ? '—' : (posts.sum.to_f / n).round(2),
           n.zero? ? '—' : "#{(100.0 * improved / n).round}%"]
        end

        Section.new(key: :movement, columns: cols(%w[domain pairs avg_first avg_latest improved]),
                    rows: rows,
                    footnote: I18n.t('reports.registry.self_sufficiency.footnote',
                                     assessed: assessed_count, pairs: matched_pairs.size))
      end

      def distribution_sections
        ['Monthly Household Income Range', 'Public Benefits Enrolled'].filter_map do |type_name|
          qt = QuantitativeType.find_by(name: type_name)
          next if qt.nil?
          rows = qt.quantitative_cases.map do |qc|
            [qc.value, ClientQuantitativeCase.where(quantitative_case_id: qc.id,
                                                    client_id: client_ids).count]
          end
          Section.new(key: :"dist_#{type_name.parameterize.underscore}",
                      columns: [type_name, I18n.t('reports.registry.self_sufficiency.columns.individuals')],
                      rows: rows,
                      footnote: I18n.t('reports.registry.self_sufficiency.point_in_time'))
        end
      end

      # [first, latest] assessment pairs for clients with >= 2 assessments whose
      # latest lands on/before period end.
      def matched_pairs
        @matched_pairs ||= begin
          by_client = Assessment.where(client_id: client_ids)
                                .where(created_at: ..period.end_date.end_of_day)
                                .order(:created_at)
                                .group_by(&:client_id)
          by_client.values.filter_map { |list| [list.first, list.last] if list.size >= 2 }
        end
      end

      def assessed_count
        @assessed_count ||= Assessment.where(client_id: client_ids)
                                      .where(created_at: ..period.end_date.end_of_day)
                                      .distinct.count(:client_id)
      end

      def score_for(assessment, domain_id)
        scores_index.dig(assessment.id, domain_id)
      end

      def scores_index
        @scores_index ||= AssessmentDomain
                          .where(assessment_id: matched_pairs.flatten.map(&:id))
                          .pluck(:assessment_id, :domain_id, :score)
                          .each_with_object({}) do |(aid, did, score), index|
          (index[aid] ||= {})[did] = score
        end
      end

      def domain_label(domain)
        domain.identity.presence || domain.name
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.self_sufficiency.columns.#{k}") }
      end
    end
  end
end
