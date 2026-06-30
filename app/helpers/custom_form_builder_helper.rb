module CustomFormBuilderHelper
  def used_custom_form?(custom_field)
    custom_field.custom_field_properties.present?
  end

  def disable_action_on_custom_form(custom_field)
    used_custom_form?(custom_field) ? 'disabled' : ''
  end

  def field_with(field,errors)
    errors.has_key?(field.to_sym) ? 'has-error' : ''
  end

  def field_message(field, errors)
    errors[field.to_sym].join(', ') if errors[field.to_sym].present?
  end

  # Matches a value that is ENTIRELY a date (optionally whitespace-padded). Anchoring
  # with \A..\z means free text that merely CONTAINS a date-like substring is left as
  # typed instead of being silently reformatted (data loss) or 500ing on an invalid date.
  CUSTOM_PROPERTY_DATE = %r{\A\s*\d{4}[-/]\d{1,2}[-/]\d{1,2}\s*\z}

  def display_custom_properties(value)
    # Build the span CONTENT as a RETURNED value and pass it to content_tag as an
    # argument. Do NOT use `content_tag :span do ... concat ... end`: under HAML's
    # capture, `concat` appends to the OUTER page buffer (the surrounding <td>), so
    # content_tag snapshots the partially-rendered page into the span -- the reported
    # "raw HTML" double-render. Array is checked FIRST (Ruby 3.2+ removed Array#=~, so
    # the old `value =~ /date/` 500'd on multi-select values). safe_join / content_tag
    # keep the user-entered PII value HTML-ESCAPED (no stored XSS) inside one clean span.
    if value.is_a?(Array)
      labels = value.reject { |i| i.to_s.empty? }
                    .map { |c| content_tag(:strong, c.to_s, class: 'label label-margin') }
      content_tag(:span, safe_join(labels, ' '))
    elsif value.is_a?(String) && value.match?(CUSTOM_PROPERTY_DATE)
      formatted = begin
                    Date.parse(value.strip).strftime('%B %d, %Y')
                  rescue Date::Error, ArgumentError
                    value
                  end
      content_tag(:span, formatted)
    else
      # safe_join escapes each text segment, then joins with the already-safe <br/> tag:
      # newline -> <br/> is preserved while the text stays escaped.
      content_tag(:span, safe_join(value.to_s.split("\n", -1), tag.br))
    end
  end

  def custom_field_frequency(frequency, time_of_frequency)
    case frequency
    when 'Daily'   then time_of_frequency.day
    when 'Weekly'  then time_of_frequency.week
    when 'Monthly' then time_of_frequency.month
    when 'Yearly'  then time_of_frequency.year
    else 0.day
    end
  end

  def frequency_note(custom_field)
    return if custom_field.frequency.empty?
    frequency = case custom_field.frequency
                when 'Daily'   then 'day'
                when 'Weekly'  then 'week'
                when 'Monthly' then 'month'
                when 'Yearly'  then 'year'
                end
    if custom_field.time_of_frequency == 1
      "This needs to be done once every #{frequency}."
    elsif custom_field.time_of_frequency > 1
      "This needs to be done once every #{pluralize(custom_field.time_of_frequency, frequency)}."
    else
      'This can be done many times and anytime.'
    end
  end
end
