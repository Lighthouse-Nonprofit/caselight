# frozen_string_literal: true
# Phase 5.5 (AC-6) SHADOW detector (SHADOW-FIRST). When config.x.enforce_least_privilege is OFF,
# log (only) what the NARROWED Ability WOULD have denied vs the live BROAD Ability, so the org can
# validate the narrowing against real usage before enforcing. Mirrors TenantBoundary: an included-do
# after_action, config.x guarded, wholly self-rescuing, and it NEVER touches the response body/status.
# Reuses the Phase-3 AccessLog.security_event! seam (no parallel mechanism).
#
# ONE event per request at most. The cheap (controller, action, role) gate runs BEFORE the
# counterfactual Ability is built, so irrelevant pages (every non-progress_notes / non-version
# request, for any role) pay nothing -- not even the narrowed Ability's queries. Metadata is
# CONTEXT-ONLY -- COUNTS, rule, role, controller, action -- NEVER record values / ids / names /
# DOB / note text.
module LeastPrivilegeShadow
  extend ActiveSupport::Concern

  # ProgressNote read paths narrowed for ec/fc/kc_manager + manager.
  PROGRESS_NOTE_READS = { 'progress_notes' => %w[index show version] }.freeze
  MANAGER_ROLES       = ['ec manager', 'fc manager', 'kc manager', 'manager'].freeze

  included do
    after_action :detect_least_privilege_divergence
  end

  private

  def detect_least_privilege_divergence
    # Only shadow while the flag is OFF; once enforcing, the narrowed Ability IS the live one. Read the SAME
    # resolved predicate Ability.least_privilege_enforced? reads (persisted override else config.x) so a UI
    # flip to ON stops shadow logging -> no split-brain.
    return if EnforcementSetting.enabled?(:enforce_least_privilege,
                                          config_default: Rails.application.config.x.enforce_least_privilege == true)
    return unless current_user && response.successful?

    # CHEAP GATE FIRST: confirm this (controller, action, role) is one the narrowing touches
    # BEFORE building the throwaway narrowed Ability (which, for a manager, costs 2 SQL queries).
    pn_relevant = PROGRESS_NOTE_READS[controller_name]&.include?(action_name) &&
                  MANAGER_ROLES.include?(current_user.roles)
    ver_relevant = action_name == 'version' && current_user.roles == 'strategic overviewer'
    return unless pn_relevant || ver_relevant

    narrowed   = Ability.new(current_user, force_least_privilege: true)
    divergence = (progress_note_divergence(narrowed) if pn_relevant) ||
                 (version_divergence(narrowed) if ver_relevant)
    return unless divergence

    AccessLog.security_event!(
      event_type: 'least_privilege_shadow',
      request: request,
      user: current_user,
      metadata: {
        'rule'         => divergence[:rule],         # 'progress_note_caseload' | 'strategic_overviewer_version'
        'role'         => current_user.roles,
        'controller'   => controller_path,
        'action'       => action_name,
        'broad_count'  => divergence[:broad_count],  # COUNTS only -- never ids/values
        'narrow_count' => divergence[:narrow_count],
        'would_deny'   => divergence[:would_deny],
        'enforced'     => false
      }
    )
  rescue => e
    # Fail-safe toward UNDER-logging: a detector miss is never allowed to alter the response.
    Rails.logger.error("[LeastPrivilegeShadow] #{e.class}: #{e.message}")
    nil
  end

  # Row-level divergence: the broad rule returns notes the narrowed (status/caseload/team) rule would
  # not. ProgressNotesController#find_client always sets @client (unconditional before_action), so we
  # compare on @client's notes; re-scope by `where(id: broad_ids)` so the narrowed COUNT is directly
  # comparable. (For show/version the counts are @client-scoped by design, not single-note.)
  def progress_note_divergence(narrowed)
    base = @client ? ProgressNote.where(client_id: @client.id)
                   : ProgressNote.where(id: (params[:id] || params[:progress_note_id]).presence)
    broad_ids = base.accessible_by(current_ability, :read).pluck(:id)
    return nil if broad_ids.empty?

    narrow_ids = base.accessible_by(narrowed, :read).where(id: broad_ids).pluck(:id)
    return nil if narrow_ids.length == broad_ids.length

    { rule: 'progress_note_caseload', broad_count: broad_ids.length,
      narrow_count: narrow_ids.length, would_deny: narrow_ids.empty? }
  end

  # Flat allow/deny: strategic_overviewer #version is broad-true, narrow-false (the rule is removed).
  # Try the conventional resource ivar; fall back to the class -- either way the narrowed ability
  # denies :version for this role, so the comparison is correct regardless of the target instance.
  def version_divergence(narrowed)
    resource = instance_variable_get("@#{controller_name.singularize}")
    target   = resource || controller_name.classify.safe_constantize
    return nil unless target
    return nil unless current_ability.can?(:version, target) && !narrowed.can?(:version, target)

    { rule: 'strategic_overviewer_version', broad_count: 1, narrow_count: 0, would_deny: true }
  end
end
