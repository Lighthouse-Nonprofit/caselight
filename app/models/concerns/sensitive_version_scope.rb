# frozen_string_literal: true

# SensitiveVersionScope -- Phase 5.3 (NIST AC-6). CustomFieldProperty has_paper_trail, so each CFP
# change writes a PaperTrail::Version whose object/object_changes carry the (Tier-5) :properties
# payload, re-exposed by data_trackers#index (item_type=CustomFieldProperty) via
# shared/version_type/_common.haml. This helper gates a PaperTrail::Version collection by the SAME
# SensitivityPolicy as every other 5.3 read path. It keys per-row on custom_field_id (live item,
# falling back to the recorded object payload for destroyed rows) -- NEVER by form_title.
#
# RECORD-AGNOSTIC / BULK: break_glass defaults to [] => emergency_only NEVER unlocked. FAIL-CLOSED:
# nil user => empty visible set => every CFP version dropped. Non-CFP versions ALWAYS pass through.
# Never raises into the request.
#
# RETURNS SURVIVING VERSION IDS (visible_version_ids) so the CONTROLLER can re-scope the original AR
# relation and keep Kaminari + Draper #decorate working. filter_versions (Array form) is retained for
# unit tests / non-relation callers.
#
# Depends on the NET-NEW CustomFieldProperty.visible_custom_field_ids delegate (seq 3); MUST land together.
module SensitiveVersionScope
  module_function

  # IDs of the versions in `versions` that survive masking, for re-scoping into an AR relation:
  #   relation.where(id: SensitiveVersionScope.visible_version_ids(relation, user: current_user))
  def visible_version_ids(versions, user:, break_glass: [])
    filter_versions(versions, user: user, break_glass: break_glass).map(&:id)
  end

  # Array of surviving versions (CFP versions not in the viewer's visible set removed; everything
  # else kept). Accepts a relation OR an Array.
  def filter_versions(versions, user:, break_glass: [])
    visible_ids = CustomFieldProperty.visible_custom_field_ids(user, break_glass: break_glass)
    versions.to_a.reject do |version|
      next false unless version.item_type == 'CustomFieldProperty'
      cf_id = custom_field_id_for(version)
      cf_id.nil? || !visible_ids.include?(cf_id)
    end
  rescue StandardError => e
    Rails.logger.error("[SensitiveVersionScope] filter_versions failed (failing closed): #{e.class}: #{e.message}")
    versions.to_a.reject { |version| version.item_type == 'CustomFieldProperty' }
  end

  def custom_field_id_for(version)
    live = (version.item rescue nil)
    return live.custom_field_id if live.respond_to?(:custom_field_id) && live.custom_field_id
    payload = version_object_hash(version)
    val = payload && (payload['custom_field_id'] || payload[:custom_field_id])
    val && val.to_i
  rescue StandardError
    nil
  end

  # Delegates to the shared SafeVersionValue ladder (single source of truth for the JSON->YAML.safe_load
  # parse; same permitted-class set). Keeps the already-a-Hash short-circuit for destroyed-row payloads
  # and the empty-value short-circuit so behaviour is preserved exactly (an empty Array/empty object -> nil).
  def version_object_hash(version)
    raw = (version.object rescue nil)
    return raw if raw.is_a?(Hash)
    return nil if raw.nil? || (raw.respond_to?(:empty?) && raw.empty?)
    SafeVersionValue.parse(raw)
  end
end
