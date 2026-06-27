class CsiStatistic
  # Phase 5.3 (NIST AC-6) — visible_levels is the viewer's Array<String> of permitted Domain
  # sensitivities. Defaults to standard-only so a caller that forgets to pass it OVER-masks
  # (fail-closed) rather than leaking restricted/emergency domain averages.
  def initialize(clients, visible_levels: [SensitivityPolicy::STANDARD])
    @clients = clients
    @assessments = Assessment.where(client: @clients)
    @visible_levels = Array(visible_levels)
  end

  def assessment_domain_score
    assessments_by_index = assessment_amount
    data = []
    assessments = []
    series = []

    assessment_amount.count.times { |i| assessments << "Assessment (#{i + 1})" }
    data << assessments

    Domain.where(sensitivity: @visible_levels).each do |domain|
      h1 = {}
      h1[:name] = domain.name
      assessment_by_value = []

      assessments_by_index.each do |a_ids|
        ad_by_assessment_index = domain.assessment_domains.where(assessment_id: a_ids)
        a_domain_score = ad_by_assessment_index.pluck(:score)
        average_domain_score = a_domain_score.size.zero? ? 0 : (a_domain_score.sum.to_f / a_domain_score.size).round(2)
        assessment_by_value << average_domain_score
      end
      h1[:data] = assessment_by_value
      series << h1
    end
    data << series
    data
  end

  private
    def assessment_amount
      data = []
      if @clients.any?
        max_count = @clients.map(&:assessments).map(&:count).max

        max_count.times do |i|
          arr = []
          @clients.each do |c|
            arr << (c.assessments.order(:created_at).to_a.at(i).blank? ? nil : c.assessments.order(:created_at).to_a.at(i).id)
          end
          data << arr.select(&:present?)
        end
      end
      data
    end

end
