# frozen_string_literal: true

# OCA feedback 2026-08-26 — Araceli's program list nests curricula under a top-level program
# ("Por Vida: Case management, Mentorship, Joven Noble, Girasol, ..."). Our Casebook import
# flattened those curricula into top-level ProgramStreams, which is what made the programs list
# look cluttered and made her list look inconsistent with the system.
#
# Curricula stay ProgramStreams rather than becoming Trackings or a new model: per-curriculum
# ENROLLMENT is what backs the cohort roster, roll call, Session Attendance, Cohorts::SESSION_TOTALS
# and the youth reports. The double enrollment (parent + curriculum) is already how the live data
# is shaped -- on the OCA box 97-100% of the clients in each curriculum are also enrolled in
# ¡Por Vida! -- so this is additive, not a remodelling.
class AddParentToProgramStreams < ActiveRecord::Migration[8.1]
  def change
    add_column :program_streams, :parent_id, :integer, null: true
    add_index  :program_streams, :parent_id

    add_foreign_key :program_streams, :program_streams, column: :parent_id, on_delete: :nullify

    # Name uniqueness moves from global to per-parent: "Mentorship" and "Groups" legitimately
    # exist under BOTH ¡Por Vida! and R.A.I.C.E.S.. Mirrors the Agency name-scoped-to-:kind
    # precedent from the school/site split. Postgres treats NULLs as distinct, so top-level
    # programs (parent_id IS NULL) need their own partial unique index to stay unique.
    add_index :program_streams, %i[name parent_id],
              unique: true, where: 'parent_id IS NOT NULL',
              name: 'index_program_streams_on_name_and_parent_id'
    add_index :program_streams, :name,
              unique: true, where: 'parent_id IS NULL',
              name: 'index_program_streams_on_name_when_top_level'
  end
end
