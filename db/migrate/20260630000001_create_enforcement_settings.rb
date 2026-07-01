class CreateEnforcementSettings < ActiveRecord::Migration[7.2]
  # Phase 5 capstone — the ADMIN FLAG-CONTROL-ROOM store (NIST AC-3 / CM-5 / AU-2).
  #
  # A single-row-per-tenant overlay that lets an org flip the three Phase-5 enforcement flags at
  # RUNTIME (config.x globals are process-global + set at boot; they cannot be flipped from a UI and
  # reset on restart). Each column is NULLABLE THREE-STATE:
  #   NULL  => NO override; the predicate defers to the config.x/ENV boot default (fail-safe = today = OFF)
  #   true  => explicit persisted ON
  #   false => explicit persisted OFF
  # We do NOT set a boolean DB default: the NULL third state is precisely what lets an absent/unset
  # value fall back to config.x instead of hard-coding OFF, and it means a FRESH tenant (no row, or a
  # row with all-NULL columns) is byte-identical to today. No seed is written — absence == config.x.
  #
  # TENANT-SCOPED: the three flags gate TENANT data (authz on tenant resources, least-privilege on tenant
  # caseloads, tenant-boundary is literally per-tenant), and the shadow evidence (AccessLog) is already
  # tenant-isolated — so each org controls + audits its OWN enforcement on its OWN subdomain. This table
  # MUST exist in EVERY Apartment tenant schema (only Organization is excluded). Production deploy, SAME
  # contract as 20260626000001/000003: `rake db:migrate` THEN `rake apartment:migrate` (bootstrap.sh
  # already runs both). A missing table FAILS SAFE in the model (EnforcementSetting.enabled? rescues to
  # the config.x default = OFF), so a tenant not-yet-migrated behaves exactly like today.
  def change
    create_table :enforcement_settings do |t|
      t.boolean :enforce_authorization   # NULL => defer to config.x.enforce_authorization (default OFF)
      t.boolean :enforce_least_privilege # NULL => defer to config.x.enforce_least_privilege (default OFF)
      t.boolean :enforce_tenant_boundary # NULL => defer to config.x.enforce_tenant_boundary (default OFF)
      t.integer :updated_by_id           # User#id of the last flip (human-facing "last changed by" audit)

      t.timestamps
    end
  end
end
