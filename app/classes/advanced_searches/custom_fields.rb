module AdvancedSearches
  class CustomFields

    include AdvancedSearchHelper

    def initialize(custom_form_ids)
      @custom_form_ids = custom_form_ids

      @number_type_list     = []
      @text_type_list       = []
      @date_type_list       = []
      @drop_down_type_list  = []

      generate_field_by_type
    end

    def render
      # Phase 5.3 — item is now [field_id_string, custom_field_id]; drop list [field_id_string, values, custom_field_id].
      number_fields       = @number_type_list.map { |item| AdvancedSearches::FilterTypes.number_options(item[0], format_label(item[0]), format_optgroup(item[0]), item[1]) }
      text_fields         = @text_type_list.map { |item| AdvancedSearches::FilterTypes.text_options(item[0], format_label(item[0]), format_optgroup(item[0]), item[1]) }
      date_picker_fields  = @date_type_list.map { |item| AdvancedSearches::FilterTypes.date_picker_options(item[0], format_label(item[0]), format_optgroup(item[0]), item[1]) }
      drop_list_fields    = @drop_down_type_list.map { |item| AdvancedSearches::FilterTypes.drop_list_options(item[0], format_label(item[0]), item[1], format_optgroup(item[0]), item[2]) }

      results = text_fields + drop_list_fields + number_fields + date_picker_fields

      results.sort_by { |f| f[:label].downcase }
    end

    def generate_field_by_type
      @custom_fields = CustomField.client_forms.where(id: @custom_form_ids)

      @custom_fields.each do |custom_field|
        cf_id = custom_field.id

        custom_field.fields.each do |json_field|
          field_id = "formbuilder_#{custom_field.form_title}_#{json_field['label']}"
          if json_field['type'] == 'text' || json_field['type'] == 'textarea'
            @text_type_list << [field_id, cf_id]
          elsif json_field['type'] == 'number'
            @number_type_list << [field_id, cf_id]
          elsif json_field['type'] == 'date'
            @date_type_list << [field_id, cf_id]
          elsif json_field['type'] == 'select' || json_field['type'] == 'checkbox-group' || json_field['type'] == 'radio-group'
            drop_list_values = []
            drop_list_values << field_id
            drop_list_values << json_field['values'].map{|value| { value['label'] => value['label'] }}
            drop_list_values << cf_id
            @drop_down_type_list << drop_list_values
          end
        end
      end
    end

    private
    def format_label(value)
      value.split('_').last
    end

    def format_optgroup(value)
      form_title = value.split('_').second
      key_word = format_header('custom_form')
      "#{form_title} | #{key_word}"
    end
  end
end
