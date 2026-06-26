# frozen_string_literal: true
# Phase 5 authorization-hardening feature flags. ALL DEFAULT OFF. Shipping the Phase 5
# code changes NO behavior until the org explicitly flips each flag (after the log-only
# shadow window and the locked allowlist/matrix). Same kill-switch pattern as
# config/initializers/two_factor.rb (enforce_mfa_for_privileged) and the AccessAudit
# access_logging_enabled flag.
#
#  enforce_authorization   => when true, ApplicationController turns on CanCanCan
#                             check_authorization + after_action :verify_authorized.
#                             Until then only the LOG-ONLY shadow after_action runs.
#  enforce_tenant_boundary => when true, TenantBoundary refuses (HTTP 409) a request
#                             whose Apartment schema != the host-derived tenant.
#                             Until then it is LOG-ONLY (security_event 'tenant_mismatch').
Rails.application.configure do
  config.x.enforce_authorization   = false unless config.x.enforce_authorization == true
  config.x.enforce_tenant_boundary = false unless config.x.enforce_tenant_boundary == true
end
