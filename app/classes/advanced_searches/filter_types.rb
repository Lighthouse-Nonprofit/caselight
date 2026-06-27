module AdvancedSearches
  class FilterTypes
    # Phase 5.3 — custom_field_id carried in the descriptor so the grid/XLS can gate the formbuilder
    # column by SensitivityPolicy WITHOUT a fragile CustomField.find_by(form_title:) round-trip. nil for
    # non-custom-form fields (client basic / program-stream).
    def self.text_options(field_name, label, group, custom_field_id = nil)
      {
        id: field_name,
        custom_field_id: custom_field_id,
        optgroup: group,
        label: label,
        type: 'string',
        operators: ['equal', 'not_equal', 'contains', 'not_contains', 'is_empty', 'is_not_empty']
      }
    end

    # Phase 4 Tier 4: equality-only string field for DETERMINISTICALLY-encrypted columns (client names).
    # Deterministic encryption supports exact equality lookup only, so the substring operators `contains`
    # / `not_contains` are intentionally omitted — they would compare against a ciphertext envelope and
    # never match. ClientBaseSqlBuilder routes `equal`/`not_equal` on these fields through the *_like
    # scopes (which resolve to `clients.id IN (?)`) rather than raw `clients.<col> = ?` SQL.
    def self.text_equal_options(field_name, label, group)
      {
        id: field_name,
        optgroup: group,
        label: label,
        type: 'string',
        operators: ['equal', 'not_equal', 'is_empty', 'is_not_empty']
      }
    end

    def self.number_options(field_name, label, group, custom_field_id = nil)
      {
        id: field_name,
        custom_field_id: custom_field_id,
        optgroup: group,
        label: label,
        type: 'integer',
        operators: ['equal', 'not_equal', 'less', 'less_or_equal', 'greater', 'greater_or_equal', 'between', 'is_empty', 'is_not_empty']
      }
    end

    def self.date_picker_options(field_name, label, group, custom_field_id = nil)
      {
        id: field_name,
        custom_field_id: custom_field_id,
        optgroup: group,
        label: label,
        type: 'date',
        operators: ['equal', 'not_equal', 'less', 'less_or_equal', 'greater', 'greater_or_equal', 'between', 'is_empty', 'is_not_empty'],
        plugin: 'datepicker',
        plugin_config: {
          format: 'yyyy-mm-dd',
          todayBtn: 'linked',
          todayHighlight: true,
          autoclose: true
        }
      }
    end

    def self.drop_list_options(field_name, label, values, group, custom_field_id = nil)
      {
        id: field_name,
        custom_field_id: custom_field_id,
        optgroup: group,
        label: label,
        type: 'string',
        input: 'select',
        values: values,
        operators: ['equal', 'not_equal', 'is_empty', 'is_not_empty']
      }
    end
  end
end
