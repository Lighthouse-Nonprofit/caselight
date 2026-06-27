class CreateBreakGlassGrants < ActiveRecord::Migration[7.2]
  # Phase 5.4 — BREAK-GLASS emergency_only access (NIST AC-3, AC-6(2)/(9), AU-2).
  #
  # RENUMBERED to 20260626000003 to avoid a DuplicateMigrationVersionError: 20260626000001 is the
  # 5.2 add_sensitivity_to_custom_fields and 20260626000002 is the 5.2b add_sensitivity_to_domains.
  #
  # A break_glass_grant is a short-lived (1h), self-service emergency elevation that widens one
  # user's view of emergency_only-classified custom fields on ONE record (polymorphic
  # custom_formable: Client/Family/Partner) — and optionally one custom_field_id on it. The grant is
  # the ONLY thing that makes an emergency_only field visible (SensitivityPolicy denies it by default).
  #
  # TENANT-SCOPED: case data lives in PER-TENANT Postgres schemas (Apartment; only Organization
  # excluded). This table MUST exist in EVERY tenant schema. Production deploy: `rake db:migrate`
  # then `rake apartment:migrate`, then `rake break_glass:smoke` (asserts the table in every tenant;
  # aborts if missing). A missing table FAILS CLOSED in the model (deny emergency_only).
  #
  # COLUMNS: user_id (the actor); custom_formable_type/id (the record — NOT FK, polymorphic +
  # friendly_id slug resolved to id in the controller); custom_field_id (OPTIONAL narrowing to one
  # emergency_only form; NULL == all emergency_only forms on the record); reason (MANDATORY
  # justification, NON-PII context — also copied into AccessLog metadata, never a field VALUE);
  # expires_at (NOT NULL; created_at + 1.hour; the `active` scope is expires_at > now).
  def change
    create_table :break_glass_grants do |t|
      t.integer  :user_id,              null: false
      t.string   :custom_formable_type, null: false
      t.integer  :custom_formable_id,   null: false
      t.integer  :custom_field_id,      null: true
      t.text     :reason,               null: false
      t.datetime :expires_at,           null: false

      t.timestamps
    end

    add_index :break_glass_grants, %i[user_id custom_formable_type custom_formable_id expires_at], name: 'idx_bgg_user_record_active'
    add_index :break_glass_grants, :expires_at, name: 'idx_bgg_expires_at'
  end
end
