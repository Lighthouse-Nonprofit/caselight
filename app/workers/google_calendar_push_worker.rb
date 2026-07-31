# Data-task batch C5 — carries GoogleCalendarPush deltas off-request (house pattern:
# tenant short_name travels as an argument, AdminWorker precedent). Idempotent per
# (op, task, user): upsert re-reads the task + state row; delete tolerates already-gone.
class GoogleCalendarPushWorker
  include Sidekiq::Worker
  sidekiq_options queue: 'default', retry: 3

  def perform(op, short_name, task_id, user_id, google_event_id = nil)
    return unless GoogleCalendarPush.enabled?
    Organization.switch_to short_name

    user = User.find_by(id: user_id)
    return unless user

    case op
    when 'upsert'
      return unless user.calendar_integration? && user.google_refresh_token.present?
      task = Task.find_by(id: task_id)
      return unless task # deleted between enqueue and run; the destroy hook queued the removal
      GoogleCalendarPush.new(user).upsert(task)
    when 'delete'
      return unless user.google_refresh_token.present?
      GoogleCalendarPush.new(user).remove(google_event_id)
    end
  end
end
