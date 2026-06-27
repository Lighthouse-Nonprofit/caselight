# frozen_string_literal: true

# SensitiveFields — Phase 5.3 controller helper for sensitive READ masking (NIST AC family;
# pairs with Phase 5.2 SensitivityPolicy + Phase 5.4 break-glass). Authored ONCE; included by
# clients/families/partners/users/custom_field_properties/data_trackers/api::clients/case_notes
# controllers. Idempotent re-include is a Ruby no-op.
#
# Two axes:
#   * CUSTOM-FIELD (custom_fields.sensitivity): visible_custom_field_ids[_for] — record-less /
#     record-aware (folds per-record break-glass via BreakGlassGrant when 5.4 lands).
#   * DOMAIN (domains.sensitivity): visible_domain_levels — record-less level Set; emergency_only
#     domains are NEVER unlocked (no domain break-glass path), so no break-glass plumbing here.
#
# Resilience: NEVER raise into a read request. On any policy/grant error, FAIL CLOSED (empty set /
# standard-only levels) rather than 500 or leak.
module SensitiveFields
  extend ActiveSupport::Concern

  private

  # Set<Integer> visible to current_user with NO record context (bulk paths). emergency_only never
  # unlocked here. Memoized per request.
  def visible_custom_field_ids
    @visible_custom_field_ids ||= begin
      CustomFieldProperty.visible_custom_field_ids(current_user, break_glass: [])
    rescue => e
      Rails.logger.error("[SensitiveFields] visible_custom_field_ids failed (failing closed): #{e.class}: #{e.message}")
      Set.new
    end
  end

  # Set<Integer> visible to current_user FOR a specific record, folding in any active break-glass
  # grant on that record (record-wide :all sentinel resolved to concrete emergency_only ids HERE,
  # before the policy — the policy rejects :all).
  def visible_custom_field_ids_for(record)
    CustomFieldProperty.visible_custom_field_ids(current_user, break_glass: break_glass_form_ids_for(record))
  rescue => e
    Rails.logger.error("[SensitiveFields] visible_custom_field_ids_for failed (failing closed): #{e.class}: #{e.message}")
    Set.new
  end

  # Per-record CONCRETE emergency_only custom_field_ids unlocked for current_user. Guarded with
  # defined?(BreakGlassGrant) so a missing model/table (5.4 not yet merged) FAILS CLOSED to [].
  def break_glass_form_ids_for(record)
    return [] unless current_user && record
    return [] unless defined?(BreakGlassGrant)
    raw = BreakGlassGrant.active_form_ids_for(current_user, record)
    if raw.include?(:all)
      record.custom_field_properties.joins(:custom_field)
            .where(custom_fields: { sensitivity: 'emergency_only' })
            .distinct.pluck('custom_fields.id')
    else
      raw.compact
    end
  rescue => e
    Rails.logger.error("[SensitiveFields] break_glass_form_ids_for failed (failing closed): #{e.class}: #{e.message}")
    []
  end

  # Array<String> of Domain sensitivity levels current_user may see (record-less; emergency masked
  # for all non-admin). Memoized. Fail-closed to standard-only.
  def visible_domain_levels
    @visible_domain_levels ||= begin
      SensitivityPolicy.new(current_user).visible_domain_levels
    rescue => e
      Rails.logger.error("[SensitiveFields] visible_domain_levels failed (failing closed): #{e.class}: #{e.message}")
      [SensitivityPolicy::STANDARD]
    end
  end

  # Log a denied sensitive read. Context-only metadata — NEVER values. Self-rescuing Phase-3 seam.
  def log_sensitive_field_denied(custom_field)
    return unless current_user && custom_field
    AccessLog.security_event!(
      event_type: 'sensitive_field_denied',
      request:    request,
      user:       current_user,
      metadata: {
        'custom_field_id'   => custom_field.id,
        'form_title'        => custom_field.form_title,
        'entity_type'       => custom_field.entity_type,
        'sensitivity_level' => custom_field.try(:sensitivity)
      }
    )
  end
end
