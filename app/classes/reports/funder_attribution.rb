# frozen_string_literal: true

module Reports
  # Funder Attribution v1 (both flavors) — which clients and service units are
  # countable under which funder, per period. v1 rides the existing
  # Agency ↔ ProgramStream mapping (agency_program_streams, admin-editable):
  # a funder = an Agency mapped to the programs it funds. Per-service-unit
  # attribution (one entry billed to exactly one grant) is deliberately
  # deferred — this view shows counts and OVERLAP, not invoices.
  class FunderAttribution < BaseReport
    private

    def build_sections
      [attribution_section, overlap_section]
    end

    def attribution_section
      rows = Agency.joins(:agency_program_streams).distinct.order(:name).map do |agency|
        program_ids = agency.program_streams.pluck(:id)
        served = served_client_ids(program_ids)
        units = scoped_trackings
                .where(client_enrollments: { program_stream_id: program_ids }).count
        [agency.name, agency.program_streams.order(:name).pluck(:name).join(', '),
         served.size, units]
      end
      Section.new(key: :attribution, columns: cols(%w[funder programs individuals service_units]),
                  rows: rows,
                  footnote: I18n.t('reports.registry.funder_attribution.footnote'))
    end

    # How many clients are countable under 1 / 2 / 3+ funders — the
    # grant-diversification story (and the double-count warning).
    def overlap_section
      funder_sets = Agency.joins(:agency_program_streams).distinct.map do |agency|
        served_client_ids(agency.program_streams.pluck(:id))
      end
      counts_per_client = Hash.new(0)
      funder_sets.each { |ids| ids.each { |id| counts_per_client[id] += 1 } }
      buckets = { '1' => 0, '2' => 0, '3+' => 0 }
      counts_per_client.each_value do |n|
        key = n >= 3 ? '3+' : n.to_s
        buckets[key] += 1
      end
      rows = buckets.map { |k, v| [I18n.t('reports.registry.funder_attribution.covered_by', count: k), v] }
      Section.new(key: :overlap, columns: cols(%w[bucket individuals]), rows: rows)
    end

    def cols(keys)
      keys.map { |k| I18n.t("reports.registry.funder_attribution.columns.#{k}") }
    end
  end
end
