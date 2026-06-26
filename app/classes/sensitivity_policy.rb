# app/classes/sensitivity_policy.rb
#
# Phase 5.2 (NIST AC family) — the ONE place the per-form sensitivity need-to-know matrix
# is implemented. Everything that masks custom-form values computes its visible set HERE.
#
# CONTRACT (KEYWORD second arg — agreed across 5.2/5.3/5.4):
#   SensitivityPolicy.new(user, active_break_glass_form_ids: []).visible_custom_field_ids
#     -> Set<Integer> of custom_fields.id this user may currently see.
#
# active_break_glass_form_ids MUST be an array of CONCRETE Integer custom_field_ids. The
# record-wide grant sentinel (:all from BreakGlassGrant.active_form_ids_for) is resolved to
# concrete emergency_only ids by the READ-PATH caller BEFORE it reaches this policy, so this
# class never receives :all and never loads a record.
#
# It answers the FORM-level question only. The RECORD-level question (caseload/active-status/
# subtree) is enforced SEPARATELY by the existing CanCan :read ability on each read path —
# visible_to is layered on a record the caller already authorized. This is why a denied
# cross-caseload break-glass cannot be laundered through here: the break-glass controller
# verifies :read on the record BEFORE a form id ever enters active_break_glass_form_ids.
#
# MATRIX (locked org decisions):
#   * admin .................. all (standard + restricted + emergency_only)
#   * strategic_overviewer ... standard ONLY (never restricted, never emergency — even with a grant)
#   * case_worker / ec|fc|kc|able|manager ... standard + restricted; emergency_only ONLY for the
#                              specific forms in active_break_glass_form_ids
#   * any other / nil ........ standard only (fail-safe)
class SensitivityPolicy
  STANDARD       = 'standard'.freeze
  RESTRICTED     = 'restricted'.freeze
  EMERGENCY_ONLY = 'emergency_only'.freeze

  # Role strings (match User::ROLES) that may see `restricted` on records they can already :read.
  RESTRICTED_ROLES = [
    'case worker', 'able manager', 'ec manager', 'fc manager', 'kc manager', 'manager'
  ].freeze

  attr_reader :user, :active_break_glass_form_ids

  def initialize(user, active_break_glass_form_ids: [])
    @user = user
    # Concrete integer ids only; reject the legacy :all sentinel defensively (caller resolves it).
    @active_break_glass_form_ids =
      Set.new(Array(active_break_glass_form_ids).reject { |x| x == :all }.map(&:to_i))
  end

  def visible_custom_field_ids
    Set.new(visible_scope.pluck(:id))
  end

  def visible_custom_fields
    visible_scope
  end

  def can_see?(custom_field_or_id)
    id = custom_field_or_id.respond_to?(:id) ? custom_field_or_id.id : custom_field_or_id.to_i
    visible_custom_field_ids.include?(id)
  end

  private

  def visible_scope
    return CustomField.all if user&.admin?

    base = CustomField.where(sensitivity: visible_levels)

    if emergency_break_glass_eligible? && active_break_glass_form_ids.any?
      base = base.or(CustomField.where(sensitivity: EMERGENCY_ONLY, id: active_break_glass_form_ids.to_a))
    end
    base
  end

  def visible_levels
    if user&.strategic_overviewer?
      [STANDARD]
    elsif restricted_role?
      [STANDARD, RESTRICTED]
    else
      [STANDARD]
    end
  end

  # Only restricted-set roles may self-elevate. strategic_overviewer is NOT (standard-only,
  # even WITH a spurious grant id). nil user: no.
  def emergency_break_glass_eligible?
    restricted_role?
  end

  def restricted_role?
    return false if user.nil?
    RESTRICTED_ROLES.include?(user.roles)
  end
end
