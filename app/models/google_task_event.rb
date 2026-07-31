# Data-task batch C5 — per-(task, user) Google Calendar sync state for the rebuilt push.
# Rows are written only by GoogleCalendarPush after a successful insert; FKs cascade with
# the task/user, so a row existing means "this user's Google calendar has this event id".
class GoogleTaskEvent < ActiveRecord::Base
  belongs_to :task
  belongs_to :user

  validates :google_event_id, presence: true
  validates :user_id, uniqueness: { scope: :task_id }
end
