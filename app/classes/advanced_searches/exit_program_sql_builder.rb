module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # LeaveProgram.properties is now NON-DETERMINISTICALLY encrypted. Same scope (joins(:client_enrollment),
  # this program_stream's leave_programs) and same { id: 'clients.id IN (?)', values: client_ids } contract;
  # client_id read THROUGH the join. PERF FLAG: O(n)-decrypt over this program's exit rows.
  #
  # PRE-EXISTING INCONSISTENCY (PRESERVED ON PURPOSE — see Tier 5 residual risks): the original #initialize
  # NEVER assigned @type (verified in source), so its `integer?` was always nil/false and EVERY numeric
  # comparison was a TEXT (lexicographic) compare — unlike the custom-form/enrollment/tracking builders
  # which cast ::int when type=='integer'. To avoid silently CHANGING existing pilot exit-search results,
  # we reproduce that exact text behaviour by passing `type: nil` to PropertiesFilter (=> never numeric).
  # The dead `format_value` method and the unused @type read in the original are dropped. The original
  # also did NOT gsub-escape @value (a raw-SQL injection footgun the Ruby rewrite incidentally closes). If
  # the org WANTS numeric exit-field ordering, that is a behaviour change to decide explicitly (flagged),
  # not a silent side effect of Tier 5.
  class ExitProgramSqlBuilder

    def initialize(program_stream_id, rule)
      @program_stream_id = program_stream_id
      field     = rule['field']
      @field    = field.split('_').last # RAW key (Ruby Hash lookup; no SQL escaping needed)
      @operator = rule['operator']
      @value    = rule['value']
      # @type deliberately NOT read from the rule — preserves the original always-TEXT behaviour.
    end

    def get_sql
      sql_string = 'clients.id IN (?)'
      leave_programs = LeaveProgram
                       .joins(:client_enrollment)
                       .includes(:client_enrollment)
                       .where(program_stream_id: @program_stream_id)

      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: nil) # nil => always TEXT compare
                .select(leave_programs)

      client_ids = matched.map { |lp| lp.client_enrollment&.client_id }.compact.uniq
      { id: sql_string, values: client_ids }
    end
  end
end
