class AddSensitivityToCustomFields < ActiveRecord::Migration[7.2]
  # Phase 5.2 (NIST AC family) — per-FORM sensitivity classification for the SLO for HOME
  # custom-form taxonomy. One custom_fields row = one form = one sensitivity level
  # (the masking unit is custom_field_id; every read path already groups by it).
  #
  # THREE levels (CustomField::SENSITIVITY_LEVELS): standard / restricted / emergency_only.
  #   * NOT NULL + default 'standard' => every existing AND future form is classified the
  #     moment the column exists. Fail-safe default is the LEAST sensitive that is still
  #     gated by record-level :read (standard is visible to anyone who can :read the record);
  #     the classification rake then RAISES the org-ratified seed forms to restricted /
  #     emergency_only, and the form-builder sensitivity picker (5.2b) lets admins set it on
  #     new forms so nothing stays mis-classified. A form nobody classified stays 'standard'
  #     (visible to the record's authorized readers) rather than silently emergency-locking
  #     real data or silently exposing it above its record ACL.
  #   * indexed: SensitivityPolicy / CustomFieldProperty.visible_to filter by sensitivity on
  #     every read path (show group_by, the datagrid, the serializer set, version history).
  #
  # TENANT-SCOPED: custom_fields lives in EACH tenant schema (Apartment excludes only
  # Organization). Production MUST apply PER TENANT via `rake apartment:migrate` IN ADDITION
  # to `rake db:migrate` — same contract as the Tier 2-5 column migrations.
  def up
    add_column :custom_fields, :sensitivity, :string, null: false, default: 'standard'
    add_index  :custom_fields, :sensitivity
  end

  def down
    remove_index  :custom_fields, :sensitivity
    remove_column :custom_fields, :sensitivity
  end
end
