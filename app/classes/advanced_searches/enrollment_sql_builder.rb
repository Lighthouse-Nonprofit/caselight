module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # ClientEnrollment.properties is now NON-DETERMINISTICALLY encrypted, so the old JSONB predicates are
  # impossible. Same scope + same { id: 'clients.id IN (?)', values: client_ids } contract; operator x
  # type semantics reproduced in AdvancedSearches::PropertiesFilter. POAM-024 CLOSED (A4): served
  # from the deterministic search-entry sidecar via PropertiesFilter#apply.
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

      # POAM-024 (A3): #apply returns the scope narrowed to matches; project with pluck.
      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: @type)
                .apply(client_enrollments)

      client_ids = matched.pluck(:client_id).uniq
      { id: sql_string, values: client_ids }
    end
  end
end
