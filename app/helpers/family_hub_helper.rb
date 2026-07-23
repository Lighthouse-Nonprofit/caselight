# UX round 3 (B1) — helpers for the persistent family hub header (families/_family_header.haml).
# Deliberately mirrors ClientHubHelper rather than abstracting over it: the two headers share
# CSS (.client-hub__*) but their identity strips, action gates, and tab sets diverge.
module FamilyHubHelper
  # Which family hub tab the current controller belongs to. forms + custom_field_properties
  # both light the Forms tab so drilling into a form's entries keeps it lit. (The same two
  # controller names exist in ClientHubHelper::HUB_TABS — disambiguation happens at the render
  # site, which picks the header partial by @custom_formable type.)
  FAMILY_HUB_TABS = {
    'families'                => :overview,
    'forms'                   => :forms,
    'custom_field_properties' => :forms,
    'family_notes'            => :notes,
    'family_alerts'           => :alerts
  }.freeze

  def family_hub_active_tab
    FAMILY_HUB_TABS[controller_name]
  end

  # Filled family forms the current viewer may see, grouped by form — drives the Forms tab
  # chip. Same Phase-5.3 record-aware visibility as the client hub. Memoized per request.
  def family_hub_forms(family)
    @family_hub_forms ||= family.custom_field_properties
                                .includes(:custom_field)
                                .where(custom_field_id: visible_custom_field_ids_for(family).to_a)
                                .group_by(&:custom_field_id)
                                .sort_by { |_, props| props.first.custom_field.form_title.to_s }
                                .to_h
  end
end
