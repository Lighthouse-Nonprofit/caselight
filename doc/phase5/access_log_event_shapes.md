# Phase 5 - new AccessLog event_type vocabulary (decision-independent shapes)

Reuses AccessLog.security_event!(event_type:, request:, user:, metadata:). event_type is a
free String; extend the documented vocabulary in access_log.rb (currently read /
login_failure / account_locked / access_denied).

HARD RULE: metadata carries non-sensitive CONTEXT only - ids, types, form_title,
sensitivity_level, reason. NEVER a field VALUE (no names/DOB/notes/document contents).

## break_glass - an emergency_only field was unlocked. AUDIT MUST BE WRITTEN BEFORE THE
## BreakGlassGrant is created (fail-closed: no audit => no access; the grant is Postgres,
## the log is Mongo, no shared transaction). Do NOT rescue-and-continue a log failure.
  metadata: { custom_formable_type, custom_formable_id, custom_field_id, form_title,
              sensitivity_level: 'emergency_only', reason, expires_at }

## sensitive_field_denied - a restricted/emergency field was withheld
  metadata: { custom_formable_type, custom_formable_id, custom_field_id, form_title,
              sensitivity_level, reason: 'role_not_permitted' | 'no_active_break_glass' }

## tenant_mismatch - the defense-in-depth boundary assertion failed (Phase 5d)
  metadata: { expected_tenant, current_tenant, controller, action, enforced }

## authorization_not_performed - verify_authorized cutover safety net (Phase 5a)
  metadata: { reason, controller, action }  # logged by the ApplicationController rescue

Also: add 'tenant_mismatch' + 'authorization_not_performed' (and later 'break_glass' /
'sensitive_field_denied') to the taxonomy comment in app/models/access_log.rb so the audit
vocabulary stays one coherent documented set. All new types inherit the WORM before_update/
before_destroy guards and the lib/tasks/audit.rake retention purge automatically.
