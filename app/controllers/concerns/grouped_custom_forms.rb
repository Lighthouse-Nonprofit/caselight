# Investor UX round (2026-07) — shared grouping for a record's filled custom forms.
# Extracted from FormsController#index so clients#show (the Overview form sections) renders
# the same visibility-filtered grouping without duplicating the query.
module GroupedCustomForms
  extend ActiveSupport::Concern

  # One { custom_field_id => [properties] } hash, restricted to the given visible set and
  # sorted by form title. `visible` decides the sensitivity posture: FormsController passes
  # the RECORD-AWARE set (an active break-glass grant folds in); the Overview passes the
  # RECORD-LESS set so emergency grants never render inline outside the audited surfaces
  # (over-masks, never leaks).
  def grouped_visible_forms(record, visible)
    record.custom_field_properties
          .includes(:custom_field)
          .where(custom_field_id: visible.to_a)
          .group_by(&:custom_field_id)
          .sort_by { |_, props| props.first.custom_field.form_title.to_s }
          .to_h
  end
end
