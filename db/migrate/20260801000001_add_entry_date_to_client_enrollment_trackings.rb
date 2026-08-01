# Youth-flavor batch Y2(a) — tracking entries get a real, backdatable service date.
# Until now an entry was stamped only by created_at (when it was TYPED, not when the
# session happened): late data entry lied, and historical imports (Casebook: ~4,600
# dated service entries) would be impossible to bring over honestly. Backfill = the
# created_at date in the app zone, so existing timelines don't move.
class AddEntryDateToClientEnrollmentTrackings < ActiveRecord::Migration[8.1]
  def up
    add_column :client_enrollment_trackings, :entry_date, :date
    execute <<~SQL
      UPDATE client_enrollment_trackings
      SET entry_date = (created_at AT TIME ZONE 'UTC' AT TIME ZONE 'America/Los_Angeles')::date
    SQL
    change_column_null :client_enrollment_trackings, :entry_date, false
    add_index :client_enrollment_trackings, :entry_date, name: 'idx_cet_entry_date'
  end

  def down
    remove_index :client_enrollment_trackings, name: 'idx_cet_entry_date'
    remove_column :client_enrollment_trackings, :entry_date
  end
end
