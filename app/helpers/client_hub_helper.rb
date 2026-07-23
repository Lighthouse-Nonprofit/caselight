# UX rung 4 — helpers for the persistent client hub header (clients/_client_header.haml).
module ClientHubHelper
  # Which hub tab the current controller belongs to. The programs family covers the
  # enrollment/exit/tracking controllers so drilling into a program keeps the Programs tab lit.
  HUB_TABS = {
    'clients'                          => :overview,
    'client_enrollments'               => :programs,
    'client_enrolled_programs'         => :programs,
    'leave_programs'                   => :programs,
    'leave_enrolled_programs'          => :programs,
    'client_enrollment_trackings'      => :programs,
    'client_enrolled_program_trackings' => :programs,
    'forms'                            => :forms,
    'custom_field_properties'          => :forms,
    'case_notes'                       => :case_notes,
    'assessments'                      => :assessments,
    'tasks'                            => :tasks
  }.freeze

  def client_hub_active_tab
    HUB_TABS[controller_name]
  end

  # Active break-glass grants the current viewer holds on `client` — feeds the header's
  # expiry chip on every hub page. Fail-closed to none (missing table / any error).
  def client_hub_active_grants(client)
    @client_hub_active_grants ||= begin
      defined?(BreakGlassGrant) ? BreakGlassGrant.for_user_and_record(current_user, client).active.order(:expires_at).to_a : []
    rescue StandardError
      []
    end
  end

  # Filled custom forms the current viewer may see for `client`, grouped by form — feeds the
  # header's Forms dropdown on every hub page. Gated on the Phase-5.3 record-aware visible
  # set (visible_custom_field_ids_for is exposed as a helper_method by SensitiveFields);
  # emergency-only forms the viewer could break-glass into are NOT listed here (that
  # affordance lives on the show page). Memoized per request.
  def client_hub_forms(client)
    @client_hub_forms ||= client.custom_field_properties
                                .includes(:custom_field)
                                .where(custom_field_id: visible_custom_field_ids_for(client).to_a)
                                .group_by(&:custom_field_id)
                                .sort_by { |_, props| props.first.custom_field.form_title.to_s }
                                .to_h
  end
end
