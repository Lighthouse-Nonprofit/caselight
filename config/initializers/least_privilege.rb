# frozen_string_literal: true
# Phase 5.5 least-privilege narrowing (NIST AC-6). Same kill-switch pattern as
# config/initializers/authorization_enforcement.rb (enforce_authorization /
# enforce_tenant_boundary) and two_factor.rb (enforce_mfa_for_privileged).
#
# DEFAULT OFF: with the flag off the Ability rule set is byte-identical to today
# (zero behavior change) AND ApplicationController logs (only) what the narrowed
# rules WOULD have denied -- event_type 'least_privilege_shadow', context-only
# metadata, never record values -- so the org can validate the narrowing against
# real usage before enforcing.
#
# Flip to true to ENFORCE:
#   * strategic_overviewer loses `can :version, :all` (NO paper_trail history) and
#     `can :read, DataTracker` (the org-wide version dashboard);
#   * ec/fc/kc_manager + manager `can :read, ProgressNote` is scoped to their
#     program-status-OR-caseload (ec/fc/kc) / managed team (manager) need-to-know.
# Fully reversible -- no migration, no stored state; flipping back to false on the
# next Ability build (current_ability is per-request) restores the broad rules.
Rails.application.configure do
  config.x.enforce_least_privilege = false unless config.x.enforce_least_privilege == true
end
