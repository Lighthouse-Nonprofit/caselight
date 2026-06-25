class ChangeTier5PropertiesJsonbToText < ActiveRecord::Migration[7.2]
  # Phase 4 Tier 5 (FINAL) — FedRAMP SC-28 / SOC 2 C1.1.
  #
  # The polymorphic CUSTOM-FORM value store and the program-stream form value stores live in jsonb
  # `.properties` columns. Tier 5 ENCRYPTS them NON-DETERMINISTICALLY (see the four models). AR Encryption
  # is WRITE-TIME over the SERIALIZED form: `attribute :properties, :json` JSON-encodes the Hash to a
  # String, then `encrypts :properties` wraps that with the encrypted type whose #serialize produces a
  # base64 JSON ENVELOPE STRING ({"p":..,"h":..}). That envelope is a STRING and CANNOT live in a `jsonb`
  # column (jsonb would try to parse / re-canonicalize it and corrupt the ciphertext). So every target
  # column is widened jsonb -> :text. Same data-shape widening as the merged Tier 2 (20260625000001),
  # Tier 3 (20260625000002) and Tier 4 (20260625000003) migrations — but here the FROM type is jsonb.
  #
  # DEFAULT: jsonb default `{}` -> TEXT default the literal two-char string '{}'. WHY '{}' and not NULL:
  #   * `attribute :properties, :json` parses the stored text through JSON — '{}' -> {} (empty Hash),
  #     exactly what every consumer expects (`record.properties[key]`, and the form partials'
  #     `f.simple_fields_for :properties, OpenStruct.new(record.properties)` which BLOWS UP on nil).
  #   * NULL would make `.properties` return nil and break OpenStruct.new(nil).
  #   * An un-backfilled legacy '{}' text value is NOT a ciphertext envelope, so encryption:verify
  #     correctly flags it as a straggler (good) while it still READS fine under
  #     support_unencrypted_data=true (the :json type parses '{}' -> {}). After the Tier-5 backfill the
  #     value becomes an envelope of the empty Hash and verify passes.
  #
  # USING clause: `properties::text` losslessly renders the jsonb value to its canonical text form ('{}',
  # or the JSON for any populated row). The column still holds PLAINTEXT JSON here (encryption is
  # write-time; the encryption:backfill rake re-writes rows AFTER this deploys).
  #
  # NO INDEXES: none of these four `.properties` columns is indexed (verified against db/schema.rb — only
  # FK/association indexes exist on these tables). The raw JSONB operators the advanced-search builders
  # used relied on no index (seq scans today), and those builders are rewritten to in-Ruby
  # decrypt-and-filter, so there is nothing to re-create.
  #
  # TENANT-SCOPED: all four tables live in EACH tenant schema (Apartment excludes only Organization).
  # Production MUST apply PER TENANT via `rake apartment:migrate` in ADDITION to `rake db:migrate`.
  # Deploy order on the box (mirror Tier 2/3/4):
  #   deploy code (models + rewritten builders + consumer fixes) -> db:migrate + apartment:migrate ->
  #   rake encryption:backfill TIER=5 CONFIRM=1 -> rake encryption:verify TIER=5
  #   (all under support_unencrypted_data=true; do NOT flip strict mode until verify PASSes for EVERY tier).
  #
  # Unlike Tier 3 (email login) this is NOT a login-blocker; an un-backfilled row reads fine in the
  # window. The search-builder rewrite reads the DECRYPTED Hash, so a half-migrated table searches
  # correctly throughout (plaintext rows pass through the :json type, ciphertext rows decrypt).
  TIER5_TABLES = %i[custom_field_properties client_enrollments client_enrollment_trackings leave_programs].freeze

  def up
    TIER5_TABLES.each do |table|
      # cast existing jsonb to text so row data is preserved verbatim ({} -> '{}', {"a":1} -> its JSON text);
      # reset the default to the TEXT literal '{}' (the jsonb {} default does not survive the type change).
      change_column table, :properties, :text, default: '{}', using: 'properties::text'
    end
  end

  def down
    # WARNING (same as every Tier 1-4 down): narrowing text -> jsonb is SAFE ONLY BEFORE the Tier-5
    # backfill writes ciphertext. AFTER the backfill the column holds base64 envelope STRINGS, which are
    # NOT valid jsonb, and `USING properties::jsonb` will RAISE (invalid input syntax for type json),
    # leaving the migration half-applied. Only run this down on a still-plaintext column. The jsonb
    # default `{}` is restored.
    TIER5_TABLES.each do |table|
      change_column table, :properties, :jsonb, default: {}, using: 'properties::jsonb'
    end
  end
end
