module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # ClientEnrollmentTracking.properties is now NON-DETERMINISTICALLY encrypted. The Active-enrollment join
  # filter is PRESERVED (only trackings whose enrollment is Active are considered), and client_id is read
  # THROUGH the join (tracking rows carry no client_id). Same { id: 'clients.id IN (?)', values: client_ids }
  # contract; operator x type semantics in AdvancedSearches::PropertiesFilter. POAM-024 CLOSED (A4):
  # served from the deterministic search-entry sidecar via PropertiesFilter#apply.
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
      # SAME scope as before, including the Active-enrollment filter (the join stays LIVE on the
      # relation, so enrollment-status flips after tracking writes need no denormalization).
      # POAM-024 (A3): the includes(:client_enrollment) preload is gone — no code path instantiates
      # the association anymore; client_id is plucked THROUGH the join below.
      client_enrollment_trackings = ClientEnrollmentTracking
                                    .joins(:client_enrollment)
                                    .where(client_enrollments: { status: 'Active' }, tracking_id: @tracking_id)

      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: @type)
                .apply(client_enrollment_trackings)

      # client_id comes through the join (preserves the old pluck('client_enrollments.client_id')).
      client_ids = matched.pluck('client_enrollments.client_id').compact.uniq
      { id: sql_string, values: client_ids }
    end
  end
end
