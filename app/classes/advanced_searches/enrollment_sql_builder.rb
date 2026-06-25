module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # ClientEnrollment.properties is now NON-DETERMINISTICALLY encrypted, so the old JSONB predicates are
  # impossible. Same scope + same { id: 'clients.id IN (?)', values: client_ids } contract; operator x
  # type semantics reproduced in AdvancedSearches::PropertiesFilter. PERF FLAG: O(n)-decrypt over the
  # program-stream's enrollments — fine at pilot volume, revisit before real-data scale.
  class EnrollmentSqlBuilder

    def initialize(program_stream_id, rule)
      @program_stream_id = program_stream_id
      field     = rule['field']
      @field    = field.split('_').last # RAW key (Ruby Hash lookup; no SQL escaping needed)
      @operator = rule['operator']
      @value    = rule['value']         # scalar String or [first, last] Array
      @type     = rule['type']
    end

    def get_sql
      sql_string = 'clients.id IN (?)'
      client_enrollments = ClientEnrollment.where(program_stream_id: @program_stream_id)

      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: @type)
                .select(client_enrollments)

      client_ids = matched.map(&:client_id).uniq
      { id: sql_string, values: client_ids }
    end
  end
end
