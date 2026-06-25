class ChangeFamilyCaseHistoryToText < ActiveRecord::Migration[7.2]
  # Phase 4 Tier 1 (SC-28): families.case_history is being encrypted with non-deterministic
  # ActiveRecord Encryption. The ciphertext is a base64-encoded JSON envelope (payload + per-value
  # random IV + auth tag + key reference) and is much longer than the original plaintext, so the
  # legacy `string` column (db/schema.rb line 383: `t.string "case_history", default: ""`) is too
  # small / unsafe. Widen to `text`, matching caregiver_information and every other Tier 1 narrative
  # column. No data conversion needed — varchar values cast to text losslessly, and at this point the
  # column still holds plaintext (encryption is write-time; the encryption:backfill rake re-saves
  # rows AFTER this migration deploys).
  #
  # TENANT-SCOPED: `families` lives in each tenant schema (Apartment excludes only Organization), so
  # production must apply this PER TENANT via `rake apartment:migrate` (in addition to the shared
  # `rake db:migrate`). Run order on the box: deploy code -> db:migrate + apartment:migrate ->
  # encryption:backfill -> encryption:verify.
  def up
    change_column :families, :case_history, :text, default: '', null: true
  end

  def down
    # WARNING: re-narrowing to varchar AFTER encryption would truncate ciphertext and corrupt data.
    # Only safe to run pre-backfill (while the column still holds plaintext).
    change_column :families, :case_history, :string, default: '', null: true
  end
end