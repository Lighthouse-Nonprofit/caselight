# Data-task batch (2026-07) — timed tasks for the calendar's day/week views.
#
# `completion_date` (bare date) stays CANONICAL: the overdue/today/upcoming scopes, the
# tasks#index buckets, the notification bell, and the reminder mailers all read it and
# keep working untouched. "Timed" is derived (`start_time.present?`) — no all_day column.
# `start_time` is a WALL-CLOCK time column (no date, no zone): the pilot is a single-site
# org on America/Los_Angeles (config.time_zone, set in the same PR), which removes the
# whole UTC-conversion bug class for scheduling.
#
# `remind_at` was dead on arrival: written by one modal field, read by NOTHING (no scope,
# mailer, worker, or view) — dropped rather than repurposed (it holds stale midnights).
#
# Runs under db:migrate AND apartment:migrate (schema-per-tenant).
class AddTimeFieldsToTasks < ActiveRecord::Migration[8.1]
  def change
    add_column :tasks, :start_time, :time
    add_column :tasks, :duration_minutes, :integer
    # The calendar feed range-queries tasks per visible window — first index on this column.
    add_index :tasks, :completion_date, name: 'idx_tasks_completion_date'
    remove_column :tasks, :remind_at, :datetime
  end
end
