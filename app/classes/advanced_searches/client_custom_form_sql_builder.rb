module AdvancedSearches
  # Phase 4 Tier 5 (SC-28 / SOC 2 C1.1) — REWRITTEN from raw JSONB SQL to in-Ruby decrypt-and-filter.
  # CustomFieldProperty.properties is now NON-DETERMINISTICALLY encrypted (jsonb widened to :text;
  # `attribute :properties, :json` + `encrypts :properties`). Postgres can no longer see inside the
  # ciphertext, so the old `properties -> 'f' ? 'v'` / `->> ILIKE` / `::int` predicates are impossible.
  # We load the same scoped rows and apply the SAME operator x field-type semantics in Ruby (see
  # AdvancedSearches::PropertiesFilter for the 1:1 mapping). The return shape is UNCHANGED, so
  # ClientBaseSqlBuilder / ClientAdvancedSearch are untouched.
  #
  # PERF FLAG: O(n)-decrypt over every CustomFieldProperty for the (Client, form) pair — fine at pilot
  # volume, must be revisited (blind-index sidecar / decrypted search table) before real-data scale.
  class ClientCustomFormSqlBuilder

    def initialize(selected_custom_form, rule)
      @selected_custom_form = selected_custom_form
      field     = rule['field']
      # RAW property key (last `_`-segment). No SQL quote-doubling now: PropertiesFilter compares it as a
      # literal Hash key, so use the un-escaped key (the old gsub("'","''") was for SQL only).
      @field    = field.split('_').last
      @operator = rule['operator']
      @value    = rule['value'] # scalar String or [first, last] Array (between); used as a Ruby value
      @type     = rule['type']
    end

    def get_sql
      sql_string = 'clients.id IN (?)'
      # SAME scope as before: this form's Client custom-form rows.
      custom_field_properties = CustomFieldProperty.where(custom_formable_type: 'Client',
                                                          custom_field_id: @selected_custom_form)

      matched = AdvancedSearches::PropertiesFilter
                .new(field: @field, operator: @operator, value: @value, type: @type)
                .select(custom_field_properties)

      client_ids = matched.map(&:custom_formable_id).uniq
      { id: sql_string, values: client_ids }
    end
  end
end
