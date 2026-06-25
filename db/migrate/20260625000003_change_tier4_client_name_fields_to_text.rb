class ChangeTier4ClientNameFieldsToText < ActiveRecord::Migration[7.2]
  # Phase 4 Tier 4 (FedRAMP SC-28, SOC 2 C1.1): clients.given_name / family_name / local_given_name /
  # local_family_name are now DETERMINISTICALLY encrypted (app/models/client.rb). The AR-Encryption
  # ciphertext envelope (a base64 JSON {"p":..,"h":..} payload) is far longer than a plaintext name and
  # overflows the original `varchar` (t.string, default ""), so widen all four to :text. Same
  # data-preserving widening as the Tier 2 address migration (20260625000001) and the Tier 3 user-PII
  # migration (20260625000002).
  #
  # NO index changes: none of these four columns is indexed in the current schema (verified against
  # db/schema.rb). Deterministic ciphertext is stable, so an equality index could later speed name
  # lookups, but at the pilot's client volume a seq scan is fine — adding one is deferred to keep this
  # migration purely data-shape (no behavioural coupling to the backfill).
  #
  # REVERSIBLE: down() narrows back to :string. SAFE ONLY BEFORE the Tier-4 backfill writes ciphertext —
  # afterwards a 255-char varchar would TRUNCATE the envelope and corrupt the column. Mirrors Tier 2/3.
  NAME_COLUMNS = %i[given_name family_name local_given_name local_family_name].freeze

  def up
    NAME_COLUMNS.each { |col| change_column :clients, col, :text, default: '' }
  end

  def down
    NAME_COLUMNS.each { |col| change_column :clients, col, :string, default: '' }
  end
end
