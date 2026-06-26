class AddSensitivityToDomains < ActiveRecord::Migration[7.2]
  def change
    # Phase 5.2b (NIST AC-6): per-Domain sensitivity, the assessment-side mirror of
    # custom_fields.sensitivity (added by 20260626000001_add_sensitivity_to_custom_fields).
    # The masking unit is the Domain (the reusable assessment-template row); answers
    # (assessment_domains) inherit it via ad.domain. Default 'standard' is behavior-neutral:
    # current visibility is preserved until 5.3 enforcement + the classification step land.
    # NOTE: timestamp is 20260626000002 — 20260626000001 is already taken by the landed 5.2
    # custom_fields migration; reusing it would make db:migrate SKIP this migration
    # (schema_migrations row already present).
    add_column :domains, :sensitivity, :string, null: false, default: 'standard'
    add_index  :domains, :sensitivity
  end
end
