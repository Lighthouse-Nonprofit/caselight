# Data-task batch (2026-07) — the FullCalendar feed is task-native now; the materialized
# `calendars` table (one row per task per user, populated only on create, end always
# start + 1 day) is dropped WITH its drift-bug class: rows went stale on every task
# edit/delete for any user without the Google flag, were matched by title+dates string
# equality across users, and served as the (all-day-only) Google push source. The Google
# push itself is retired in this PR and REBUILT clean in C5 on a per-(task,user) state
# table — see REMOVED-FEATURES.md.
#
# Runs under db:migrate AND apartment:migrate (schema-per-tenant).
class DropCalendars < ActiveRecord::Migration[8.1]
  def up
    drop_table :calendars
  end

  def down
    create_table :calendars do |t|
      t.string   :title
      t.datetime :start_date, precision: nil
      t.datetime :end_date, precision: nil
      t.boolean  :sync_status, default: false
      t.integer  :user_id
      t.timestamps null: false
    end
  end
end
