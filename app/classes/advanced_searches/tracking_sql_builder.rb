module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # ClientEnrollmentTracking.properties is now NON-DETERMINISTICALLY encrypted. The Active-enrollment join
  # filter is PRESERVED (only trackings whose enrollment is Active are considered), and client_id is read
  # THROUGH the join (tracking rows carry no client_id). Same { id: 'clients.id IN (?)', values: client_ids }
  # contract; operator x type semantics in AdvancedSearches::PropertiesFilter. PERF FLAG: O(n)-decrypt over
  # the active trackings for this tracking_id — fine at pilot volume, revisit before real-data scale.
  class TrackingSqlBuilder

    def initialize(tracking_id, rule)
      @tracking_id = tracking_id
      field     = rule['field']
      @field    = field.split('_').last # RAW key (Ruby Hash lookup; no SQL escaping needed)
      @operator = rule['operator']
      @value    = rule['value']         # scalar String or [first, last] Array
      @type     = rule['type']
    end

    def get_sql
      sql_string = 'clients.id IN (?)'
      # SAME scope as before, including the Active-enrollment filter. includes(:client_enrollment) so the
      # join row is loaded for the client_id read below without an N+1 per matched tracking.
      client_enrollment_trackings = ClientEnrollmentTracking
                                    .joins(:client_enrollment)
                                    .includes(:client_enrollment)
                                    .where(client_enrollments: { status: 'Active' }, tracking_id: @tracking_id)

      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: @type)
                .select(client_enrollment_trackings)

      # client_id comes through the join (preserves the old pluck('client_enrollments.client_id')).
      client_ids = matched.map { |t| t.client_enrollment&.client_id }.compact.uniq
      { id: sql_string, values: client_ids }
    end
  end
end
