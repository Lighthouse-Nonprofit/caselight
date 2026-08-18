# Casebook migration (owner decision 2026-08): keep program COHORTS separate. A client who ran the
# same curriculum in two terms/sites gets ONE enrollment PER cohort, not a merged one. The cohort
# identity (Site + Term) lives in the encrypted `properties`, which can't be queried — so this
# queryable `cohort` column is the dedup key for the importer (blank = the single default cohort).
class AddCohortToClientEnrollments < ActiveRecord::Migration[8.0]
  def change
    add_column :client_enrollments, :cohort, :string, default: ''
    add_index :client_enrollments, [:client_id, :program_stream_id, :cohort],
              name: 'idx_client_enrollments_cohort'
  end
end
