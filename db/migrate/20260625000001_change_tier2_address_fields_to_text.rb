class ChangeTier2AddressFieldsToText < ActiveRecord::Migration[7.2]
  # Phase 4 Tier 2 (SC-28 / SOC 2 C1.1): the address / location PII columns below are being encrypted
  # with NON-DETERMINISTIC ActiveRecord Encryption. The ciphertext is a base64-encoded JSON envelope
  # (payload + per-value random IV + auth tag + key reference) and is much longer than the original
  # plaintext, so the legacy `t.string, default: ""` columns (db/schema.rb) are too small / unsafe.
  # Widen each to `text`, matching every Tier 1 narrative column. No data conversion needed — varchar
  # values cast to text losslessly, and at this point the columns still hold plaintext (encryption is
  # write-time; the encryption:backfill rake re-saves rows AFTER this migration deploys). Mirrors
  # Tier 1's 20260624000005_change_family_case_history_to_text.rb.
  #
  # Columns (10): Client x8 — current_address, school_name, house_number, street_number, village,
  # commune, district, live_with; Family — address; Partner — address. (Family.caregiver_information /
  # case_history and the Client narrative columns were already encrypted/widened in Tier 1 and are
  # untouched here. Note: partners.commune is a SEPARATE column NOT in the Tier 2 set — left as varchar.)
  #
  # TENANT-SCOPED: clients/families/partners all live in each tenant schema (Apartment excludes only
  # Organization), so production must apply this PER TENANT via `rake apartment:migrate` in addition to
  # the shared `rake db:migrate`. Run order on the box: deploy code -> db:migrate + apartment:migrate ->
  # encryption:backfill TIER=2 CONFIRM=1 -> encryption:verify TIER=2.
  CLIENT_COLUMNS = %i[current_address school_name house_number street_number
                      village commune district live_with].freeze

  def up
    CLIENT_COLUMNS.each do |col|
      change_column :clients, col, :text, default: '', null: true
    end
    change_column :families, :address, :text, default: '', null: true
    change_column :partners, :address, :text, default: '', null: true
  end

  def down
    # WARNING: re-narrowing to varchar AFTER encryption would truncate ciphertext and corrupt data.
    # Only safe to run pre-backfill (while the columns still hold plaintext).
    CLIENT_COLUMNS.each do |col|
      change_column :clients, col, :string, default: '', null: true
    end
    change_column :families, :address, :string, default: '', null: true
    change_column :partners, :address, :string, default: '', null: true
  end
end
