# Demo UX polish — a real program LIFECYCLE status (pending / active / completed), owner-set.
# Distinct from the pre-existing `completed` boolean, which is an internal CONFIG-readiness flag
# (has enrollment + exit + trackings). "completed" here means the cohort ran and is no longer
# running. Existing programs are in use → default 'active'.
class AddStatusToProgramStreams < ActiveRecord::Migration[8.0]
  def change
    add_column :program_streams, :status, :string, default: 'active', null: false
  end
end
