# frozen_string_literal: true
# Phase 5.6 (AC-3) GLOBAL AUTHORIZATION CUTOVER -- SHADOW detector (SHADOW-FIRST). CanCanCan's
# check_authorization ONLY raises when config.x.enforce_authorization is ON; while OFF it is inert. This
# concern is the always-on (while-flag-OFF) detector that LOGS which actions WOULD fail the mandatory
# check, so the org validates the allowlist against real usage BEFORE flipping. Mirrors TenantBoundary /
# LeastPrivilegeShadow EXACTLY: an included-do after_action, config.x-guarded, wholly self-rescuing, and
# it NEVER touches the response body/status. Reuses the Phase-3 AccessLog.security_event! seam. ONE event
# per request at most.
#
# It keys off the IDENTICAL signal check_authorization uses: the controller ivar @_authorized.
# authorize!/authorize_resource/load_and_authorize_resource set it during the request;
# skip_authorization_check sets it via its own before_action. So @_authorized defined => the action
# authorized OR is allowlisted => WOULD PASS (no event); undefined => WOULD 403 under enforcement => log.
#
# Metadata is CONTEXT-ONLY -- controller/action/role/enforced -- NEVER record values/ids/names/DOB/notes.
module AuthorizationShadow
  extend ActiveSupport::Concern

  included do
    after_action :detect_unauthorized_action
  end

  private

  def detect_unauthorized_action
    # Once enforcing, check_authorization is the live mechanism -- no shadow, no double-handling. Read the
    # SAME resolved predicate the enforcement gate reads (persisted override else config.x) so a UI flip to
    # ON stops the shadow logging -> no split-brain (enforcing via the store but still shadow-logging).
    return if EnforcementSetting.enabled?(:enforce_authorization,
                                          config_default: Rails.application.config.x.enforce_authorization == true)
    # The EXACT condition check_authorization will test when flipped ON.
    return if instance_variable_defined?(:@_authorized)

    AccessLog.security_event!(
      event_type: 'authorization_shadow',
      request: request,
      user: (current_user if respond_to?(:current_user)),
      metadata: {
        'controller' => controller_path, # context only -- NEVER record values
        'action'     => action_name,
        'role'       => (current_user&.roles),
        'enforced'   => false
      }
    )
  rescue => e
    # Fail-safe toward UNDER-logging: a detector miss must never alter the response.
    Rails.logger.error("[AuthorizationShadow] #{e.class}: #{e.message}")
    nil
  end
end
