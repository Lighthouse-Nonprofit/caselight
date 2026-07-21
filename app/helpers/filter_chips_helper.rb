# UX rung 3 — dismissible "applied filter" chips rendered above the record indexes. Hidden
# filters (the collapsed drawer) stay legible: each active grid param becomes a chip whose
# href is the current URL rebuilt WITHOUT that filter. Pure GET links — CSP-safe, zero JS.
module FilterChipsHelper
  # Grid-internal keys the controllers merge! into params[:client_grid] at construction
  # (ClientGridOptions) — never chips, never serialized into dismiss URLs.
  INTERNAL_KEYS  = %w[qType dynamic_columns visible_custom_field_ids current_user current_client column_form_builder].freeze
  # No chip for these, but they persist in dismiss URLs (sort survives a chip dismiss).
  CHIP_SKIP_KEYS = (%w[order descending page] + INTERNAL_KEYS).freeze

  def applied_filter_chips(grid_key, scope:)
    raw = params[grid_key]
    return if raw.blank? || !raw.respond_to?(:to_unsafe_h)
    active = raw.to_unsafe_h.reject { |k, v| CHIP_SKIP_KEYS.include?(k.to_s) || chip_blank?(v) }
    return if active.empty?
    content_tag :ul, class: 'filter-chips', 'aria-label' => t('shared.filters.active_filters', default: 'Active filters') do
      safe_join(active.map { |key, value| content_tag(:li, filter_chip(grid_key, key, value, scope: scope), class: 'filter-chips__item') })
    end
  end

  private

  def chip_blank?(value)
    case value
    when Array then value.all? { |v| v.to_s.strip.empty? }
    when Hash  then value.values.all? { |v| v.to_s.strip.empty? }
    else value.to_s.strip.empty?
    end
  end

  def filter_chip(grid_key, key, value, scope:)
    name = I18n.t("datagrid.columns.#{scope}.#{key}", default: key.to_s.humanize)
    text = chip_value_text(scope, key, value)
    remaining = params.to_unsafe_h.deep_dup
    remaining[grid_key.to_s] = remaining[grid_key.to_s].reject { |k, _| k.to_s == key.to_s || INTERNAL_KEYS.include?(k.to_s) }
    remaining = remaining.except('page', 'controller', 'action')
    link_to url_for(params: remaining), class: 'filter-chips__chip', rel: 'nofollow',
            'aria-label' => t('shared.filters.remove_filter', default: 'Remove filter: %{name}', name: name) do
      safe_join([text ? "#{name}: #{text}" : name,
                 content_tag(:span, '×', class: 'filter-chips__x', 'aria-hidden' => 'true')], ' ')
    end
  end

  # Chip value text for simple string filters (raw enum values map through the display
  # labels); arrays/hashes (ranges, multi-selects) show the filter name alone.
  def chip_value_text(scope, key, value)
    return unless value.is_a?(String)
    return ClientGrid::STATUS_LABELS.fetch(value, value).truncate(28) if scope.to_s == 'clients' && key.to_s == 'status'
    return Family.type_label(value).truncate(28) if scope.to_s == 'families' && key.to_s == 'family_type'
    value.truncate(28)
  end
end
