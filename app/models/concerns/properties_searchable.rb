# frozen_string_literal: true

# POAM-024 — keeps a model's *SearchEntry sidecar rows (see PropertiesSearchEntry) in lock-step with
# its Tier-5 encrypted `.properties` Hash, one row per (field_label, value element). Included by the
# four Tier-5 models (CustomFieldProperty / ClientEnrollment / ClientEnrollmentTracking / LeaveProgram).
#
# NORMALIZATION IS THE CONTRACT. `properties_search_desired_pairs` mirrors — exactly — the semantics of
# AdvancedSearches::PropertiesFilter#member? (the oracle-verified jsonb `?` reproduction):
#   * key absent            -> no rows            (matches nothing; missing-key rows are EXCLUDED by
#                                                  not_equal / is_not_empty)
#   * scalar v              -> one row v.to_s     (member? compares element.to_s / raw.to_s)
#   * array [a, b]          -> one row per DISTINCT element.to_s (jsonb `?` element membership;
#                              a JSON null element -> '' exactly like member?'s nil.to_s)
#   * nil scalar or []      -> one PRESENCE-MARKER row (value NULL): key present, matches no equality
#                              probe — member?(nil, x) is false (the nil guard), member?([], x) is
#                              false, but not_equal / is_not_empty still match the row.
# Known accepted micro-divergence (documented in PropertiesFilter too): member?'s degenerate
# `raw.to_s == value.to_s` whole-array branch (searching equal for the literal Ruby rendering of an
# array, e.g. '["a", "b"]') is not representable as element rows. The PR-A3 shadow phase proves it
# never fires in practice.
#
# THE SYNC IS A DIFF-SYNC, and that is load-bearing for the whole program: it inserts only missing
# pairs and deletes only stale rows, so a second run over unchanged data performs ZERO writes. The
# PR-A2 backfill rake calls this same method per record — which is what makes the every-deploy
# backfill provably idempotent (the #203 standard: prove it across two runs, byte-identical).
#
# Runs in after_save (INSIDE the save's transaction — record + index commit atomically), only when
# `properties` actually changed. `update_columns` writers (the encryption backfill) skip callbacks by
# design and never change plaintext, so no interaction. Deletes need no callback: the FKs are
# ON DELETE CASCADE. Entry writes create no paper_trail versions and no Mongo history (the entry
# models carry neither) — the owner models keep the audit trail.
module PropertiesSearchable
  extend ActiveSupport::Concern

  included do
    after_save :sync_properties_search_entries!, if: :saved_change_to_properties?
  end

  class_methods do
    def properties_search_entry_class
      @properties_search_entry_class ||= "#{name}SearchEntry".constantize
    end

    def properties_search_entry_foreign_key
      @properties_search_entry_foreign_key ||= :"#{name.underscore}_id"
    end
  end

  # Set of [field_label, value-or-nil] pairs the sidecar must hold for this record's current
  # decrypted properties. Pure function of the Hash — the normalization contract above.
  def properties_search_desired_pairs
    props = properties
    props = {} unless props.is_a?(Hash)

    props.each_with_object(Set.new) do |(label, raw), pairs|
      key = label.to_s
      case raw
      when nil
        pairs << [key, nil]
      when Array
        if raw.empty?
          pairs << [key, nil]
        else
          raw.each { |element| pairs << [key, element.to_s] }
        end
      else
        pairs << [key, raw.to_s]
      end
    end
  end

  # Diff-sync: insert missing pairs, delete stale/duplicate rows, touch nothing else.
  # Returns { added:, removed: } so the backfill rake can report (and prove the zero) per tenant.
  # dry_run: true computes the SAME delta without applying it — the rake's DRY-RUN mode rides this
  # so there is exactly one implementation of the diff.
  def sync_properties_search_entries!(dry_run: false)
    entry_class = self.class.properties_search_entry_class
    foreign_key = self.class.properties_search_entry_foreign_key
    desired     = properties_search_desired_pairs

    keep      = Set.new
    stale_ids = []
    entry_class.where(foreign_key => id).each do |entry|
      pair = [entry.field_label, entry.value]
      if desired.include?(pair) && !keep.include?(pair)
        keep << pair # first row for a desired pair wins; any duplicate is stale
      else
        stale_ids << entry.id
      end
    end
    missing = desired - keep

    unless dry_run
      entry_class.where(id: stale_ids).delete_all if stale_ids.any?
      missing.each do |field_label, value|
        entry_class.create!(foreign_key => id, field_label: field_label, value: value)
      end
    end

    { added: missing.size, removed: stale_ids.size }
  end
end
