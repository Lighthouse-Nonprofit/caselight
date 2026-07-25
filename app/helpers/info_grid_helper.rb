# UX round 4 (R4-3) — the app-wide label-over-value info grid (renders via shared/_info_grid).
module InfoGridHelper
  # One grid item. Rich HTML values: build with `capture do ... end` in the view and pass
  # the result. (Do NOT hang a `do` block off `items << info_item(...)` — the block binds
  # to `<<`, not to info_item.)
  def info_item(label, value = nil, full: false)
    { label: label, value: value, full: full }
  end

  # The dynamic form-field surfaces (enrollments / trackings / custom-field entries): field
  # defs are [{ 'type' =>, 'label' => }] with USER-AUTHORED labels; file fields render the
  # shared attachment list as a full-width item. Pair with variant: 'info-grid--natural-case'
  # (user-authored labels must not be shouted uppercase).
  def custom_field_info_items(fields, resource)
    Array(fields).map { |f| [f['type'], f['label']] }.map do |type, label|
      if type == 'file'
        info_item(label, render('shared/form_builder/list_attachment', label: label, resource: resource), full: true)
      else
        info_item(label, display_custom_properties(resource.properties[label]))
      end
    end
  end
end
