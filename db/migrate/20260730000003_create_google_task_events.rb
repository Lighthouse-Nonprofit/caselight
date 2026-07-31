# Data-task batch C5 — the REBUILT Google Calendar push (see REMOVED-FEATURES.md 2026-07-30:
# the legacy one-way push died with the calendars table in C2). Honest per-(task, user) sync
# state: one row per pushed event, so update/delete target the real Google event instead of
# the old title+date string matching.
class CreateGoogleTaskEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :google_task_events do |t|
      t.integer :task_id, null: false
      t.integer :user_id, null: false
      t.string  :google_event_id, null: false
      t.timestamps
      t.index %i[task_id user_id], unique: true, name: 'idx_google_task_events_task_user'
      t.index :user_id, name: 'idx_google_task_events_user'
    end
    add_foreign_key :google_task_events, :tasks, on_delete: :cascade
    add_foreign_key :google_task_events, :users, on_delete: :cascade

    # The offline-access credential for the push. Born-encrypted (encrypts, non-deterministic,
    # ENCRYPTION_TIERS tier 6) — never written as plaintext.
    add_column :users, :google_refresh_token, :text
  end
end
