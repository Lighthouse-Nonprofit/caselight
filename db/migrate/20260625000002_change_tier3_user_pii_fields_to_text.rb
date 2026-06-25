class ChangeTier3UserPiiFieldsToText < ActiveRecord::Migration[7.2]
  # Phase 4 Tier 3 (SC-28 / SOC 2 C1.1): the staff-account PII columns below are being encrypted with
  # DETERMINISTIC ActiveRecord Encryption (encrypts ..., deterministic: true). The ciphertext is a
  # base64-encoded JSON envelope (payload + deterministic IV + auth tag + key reference) far longer
  # than the original plaintext, so the legacy `t.string` columns are too small. Widen each to `text`,
  # mirroring the Tier 1/2 migrations (20260624000005 / 20260625000001). No data conversion: varchar ->
  # text is lossless, and at this point the columns still hold PLAINTEXT (encryption is write-time; the
  # encryption:backfill rake re-saves rows AFTER this deploys).
  #
  # Columns (5, all on users): email, first_name, last_name, mobile, uid.
  #   - email is the Devise login identifier (deterministic + downcase:true).
  #   - uid is a vestigial devise_token_auth column that the 2016 migration
  #     (db/migrate/20160305051724_update_user_data.rb) set equal to the email when blank — a stale
  #     plaintext email copy; it is encrypted with the SAME deterministic+downcase settings, so it must
  #     be widened too. (null:false default '' preserved.)
  #
  # EMAIL UNIQUE INDEXES — the load-bearing part (db/schema.rb has BOTH):
  #   * KEEP `index_users_on_email` (plain unique index on the raw email column). Deterministic
  #     encryption stores STABLE ciphertext, so this index keeps enforcing email uniqueness over the
  #     ciphertext exactly as it did over plaintext. Postgres preserves a plain b-tree index across a
  #     varchar->text ALTER TYPE, so change_column does NOT drop it; we leave it untouched. (Verify it
  #     still exists post-migrate via the deploy smoke check / `\d users`.)
  #   * DROP `users_email_lower` — the FUNCTIONAL unique index on `lower((email)::text) text_pattern_ops`.
  #     Once email is ciphertext, lower(email) lowercases a base64 envelope: meaningless, and redundant
  #     because downcase:true already case-folds BEFORE encryption (so 'A@x.com' and 'a@x.com' serialize
  #     to the SAME ciphertext and the plain unique index already rejects the dup case-insensitively).
  #
  # TENANT-SCOPED: users live in each tenant schema (Apartment excludes only Organization). Production
  # MUST apply PER TENANT via `rake apartment:migrate` in addition to `rake db:migrate`. Run order on
  # the box (DETERMINISTIC EMAIL => backfill is NOT optional and must precede any login):
  #   deploy code -> db:migrate + apartment:migrate -> rake encryption:backfill TIER=3 CONFIRM=1 ->
  #   rake encryption:verify TIER=3 -> confirm a real sign-in works -> reopen logins.
  # A not-yet-backfilled plaintext email row will NOT match find_for_database_authentication's
  # ciphertext equality query, so that user cannot log in until the backfill completes. Do the backfill
  # in the SAME maintenance window as this deploy, before reopening logins.

  def up
    # Drop the functional lower(email) unique index; meaningless over ciphertext (see header). Guarded
    # so a re-run / a schema where it is already absent does not fail.
    if index_name_exists?(:users, 'users_email_lower')
      remove_index :users, name: 'users_email_lower'
    end

    # email + uid are NOT NULL with default '' in the schema; preserve null:false + default. first_name/
    # last_name/mobile are nullable with default ''.
    change_column :users, :email,      :text, null: false, default: ''
    change_column :users, :uid,        :text, null: false, default: ''
    change_column :users, :first_name, :text, default: ''
    change_column :users, :last_name,  :text, default: ''
    change_column :users, :mobile,     :text, default: ''
  end

  def down
    # WARNING: re-narrowing to varchar AFTER the encryption backfill would TRUNCATE ciphertext and
    # corrupt every staff email (= lock everyone out). Only safe to run PRE-backfill, while the columns
    # still hold plaintext. The dropped lower(email) functional index is recreated for symmetry.
    change_column :users, :email,      :string, null: false, default: ''
    change_column :users, :uid,        :string, null: false, default: ''
    change_column :users, :first_name, :string, default: ''
    change_column :users, :last_name,  :string, default: ''
    change_column :users, :mobile,     :string, default: ''

    unless index_name_exists?(:users, 'users_email_lower')
      execute <<~SQL.squish
        CREATE UNIQUE INDEX users_email_lower ON users (lower((email)::text) text_pattern_ops)
      SQL
    end
  end
end