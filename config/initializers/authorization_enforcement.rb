# frozen_string_literal: true
# Phase 5 authorization-hardening feature flags. The lines below are the FAIL-SAFE fallback
# (OFF) — since 2026-07-26 the PRODUCTION default is ON via config/environments/production.rb
# (environments load before initializers; the `unless == true` guard preserves it). Dev/test
# stay shadow-only unless a spec forces the flag; per-tenant EnforcementSetting rows override
# either default via the audited admin panel. Same kill-switch pattern as
# config/initializers/two_factor.rb (enforce_mfa_for_privileged) and the AccessAudit
# access_logging_enabled flag.
#
#  enforce_authorization   => when true (Phase 5.6, AC-3), ApplicationController turns on CanCanCan
#                             check_authorization: every action must authorize a resource or be
#                             skip_authorization_check'd, else CanCan::AuthorizationNotPerformed -> the
#                             static-403 rescue. Until then only the LOG-ONLY AuthorizationShadow
#                             after_action runs. (NB: verify_authorized is a Pundit concept, NOT used here;
#                             row-level narrowing is the SEPARATE config.x.enforce_least_privilege flag.)
#  enforce_tenant_boundary => when true, TenantBoundary refuses (HTTP 409) a request
#                             whose Apartment schema != the host-derived tenant.
#                             Until then it is LOG-ONLY (security_event 'tenant_mismatch').
Rails.application.configure do
  config.x.enforce_authorization   = false unless config.x.enforce_authorization == true
  config.x.enforce_tenant_boundary = false unless config.x.enforce_tenant_boundary == true
end
