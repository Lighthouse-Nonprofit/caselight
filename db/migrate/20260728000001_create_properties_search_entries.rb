class CreatePropertiesSearchEntries < ActiveRecord::Migration[8.1]
  # POAM-024 (docs/compliance/vulnerability-poam.md) — the queryable sidecar for Tier-5 custom-form
  # search. The four `.properties` stores are encrypted NON-deterministically (20260625000004 + the
  # models), so Postgres cannot see inside them and the advanced-search builders fell back to
  # O(n)-decrypt-in-Ruby (AdvancedSearches::PropertiesFilter — flagged there). These tables are the
  # fix: ONE ROW PER (record, field-label, value-element), value encrypted DETERMINISTICALLY
  # (PropertiesSearchEntry), so the equality-family operators become indexed SQL again.
  #
  # Shape notes (load-bearing):
  #   * <owner>_id is INTEGER, not bigint — all four owner tables are `id: :serial` (int4).
  #   * field_label is PLAINTEXT text: the labels already sit in plaintext in the same schema
  #     (custom_fields.fields / program_streams.enrollment+exit_program / trackings.fields jsonb),
  #     so a digest would add zero confidentiality and destroy debuggability.
  #   * value NULL is a PRESENCE MARKER (key present holding JSON null or []) — it serves the
  #     not_equal / is_not_empty missing-key-EXCLUSION semantics without matching any equality probe.
  #   * value gets a HASH index, not btree: the column holds AR-Encryption envelopes and a long
  #     textarea answer's envelope would blow the ~2704-byte btree index-row limit AT INSERT —
  #     breaking saves, not just lookups. Hash serves =/IN (the only ops this column ever needs),
  #     has no row-size limit, and is WAL-safe on PG 17. No unique constraint for the same reason;
  #     row uniqueness is enforced by the PropertiesSearchable diff-sync write path.
  #   * FKs are ON DELETE CASCADE — deletes stay complete under dependent: :destroy chains, raw SQL
  #     and console deletes alike, with no callback discipline required. No after_destroy anywhere.
  #
  # TENANT-SCOPED like every owner table (Apartment excludes only Organization): production applies
  # this via `rake db:migrate` + `rake apartment:migrate` (bootstrap already runs both).
  # Rebuild path: the rows are DERIVED data — `rake properties_search:backfill` (PR A2) regenerates
  # them from the decrypted `.properties` at any time, so a botched table is never a data-loss event.
  TABLES = {
    custom_field_property_search_entries: {
      owner_table: :custom_field_properties, fk: :custom_field_property_id, prefix: 'cfp'
    },
    client_enrollment_search_entries: {
      owner_table: :client_enrollments, fk: :client_enrollment_id, prefix: 'ce'
    },
    client_enrollment_tracking_search_entries: {
      owner_table: :client_enrollment_trackings, fk: :client_enrollment_tracking_id, prefix: 'cet'
    },
    leave_program_search_entries: {
      owner_table: :leave_programs, fk: :leave_program_id, prefix: 'lp'
    }
  }.freeze

  def change
    TABLES.each do |table, cfg|
      create_table table do |t|
        t.integer cfg[:fk], null: false
        t.text :field_label, null: false
        t.text :value
        t.timestamps
      end

      # Explicit short names — the auto-generated ones exceed Postgres' 63-char identifier limit.
      add_index table, [cfg[:fk], :field_label], name: "idx_#{cfg[:prefix]}_se_owner_label"
      add_index table, :field_label,             name: "idx_#{cfg[:prefix]}_se_label"
      add_index table, :value, using: :hash,     name: "idx_#{cfg[:prefix]}_se_value_hash"

      add_foreign_key table, cfg[:owner_table], column: cfg[:fk], on_delete: :cascade
    end
  end
end
