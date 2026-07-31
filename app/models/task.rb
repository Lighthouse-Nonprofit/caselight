class Task < ActiveRecord::Base
  belongs_to :domain, counter_cache: true
  belongs_to :case_note_domain_group
  belongs_to :client

  has_many :case_worker_tasks, dependent: :destroy
  has_many :users, through: :case_worker_tasks
  has_many :google_task_events # C5 push state; rows cascade via DB FK (kept for before_destroy capture)

  has_paper_trail

  validates :name, presence: true
  validates :domain, presence: true
  validates :completion_date, presence: true
  # validates :user_ids, presence: true
  # Data-task batch (2026-07): timed tasks. duration only makes sense on a timed task;
  # 12h is the sane ceiling for a single work-day block.
  validates :duration_minutes, numericality: { only_integer: true, greater_than: 0, less_than_or_equal_to: 720 }, allow_nil: true
  validates :start_time, presence: { message: 'is required when a duration is set' }, if: -> { duration_minutes.present? }

  # Data-task batch (2026-07): Time.zone (America/Los_Angeles), not Date.today — the
  # server runs UTC, so bare Date flipped tasks overdue at ~5pm local.
  scope :completed,  -> { where(completed: true) }
  scope :incomplete, -> { where(completed: false) }
  scope :overdue,    -> { where('completion_date < ?', Time.zone.today) }
  scope :today,      -> { where('completion_date = ?', Time.zone.today) }
  scope :upcoming,   -> { where('completion_date > ?', Time.zone.today) }

  scope :overdue_incomplete, -> { incomplete.overdue }
  scope :today_incomplete,   -> { incomplete.today }
  scope :by_domain_id,       ->(value) { where('domain_id = ?', value) }

  scope :overdue_incomplete_ordered, -> { overdue_incomplete.order('completion_date ASC') }

  after_save :set_users, :create_task_history

  # Data-task batch C5 — the rebuilt Google push. after_commit (never in-request network):
  # deltas go to Sidekiq for every opted-in assigned user. set_users fans CaseWorkerTask
  # in after_save (same transaction), so `users` is complete by commit time. Removals are
  # captured BEFORE destroy — the FK cascade has deleted the state rows by after_commit.
  after_commit :push_google_calendar, on: %i[create update]
  before_destroy :capture_google_push_removals, prepend: true
  after_commit :push_google_calendar_removals, on: :destroy

  # Data-task batch (2026-07): the timed-task lens. completion_date owns the DAY;
  # start_time is wall-clock; the pair composes in the app zone.
  def timed?
    start_time.present?
  end

  def starts_at
    return nil unless timed?
    Time.zone.local(completion_date.year, completion_date.month, completion_date.day,
                    start_time.hour, start_time.min)
  end

  def ends_at
    return nil unless timed?
    starts_at + (duration_minutes || 60).minutes
  end

  def set_users
    client.users.map { |user| CaseWorkerTask.find_or_create_by(task_id: id, user_id: user.id) }
  end

  def self.of_user(user)
    joins(:case_worker_tasks).where(case_worker_tasks: { user_id: user.id })
  end

  def self.set_complete
    update_all(completed: true)
  end

  def self.filter(params)
    user     = User.find(params[:user_id]) if params[:user_id]
    relation = all
    relation = relation.joins(:case_worker_tasks).where(case_worker_tasks: { user_id: user.id }) if user.present?
    relation
  end

  def self.under(user, client)
    joins(:case_worker_tasks).where(case_worker_tasks: { user_id: user.id }).where(client_id: client.id)
  end

  def self.upcoming_incomplete_tasks
    Organization.all.each do |org|
      Organization.switch_to org.short_name
      user_ids = incomplete.where(completion_date: Time.zone.tomorrow).map(&:user_ids).flatten.uniq
      users    = User.where(id: user_ids)
      users.each do |user|
        CaseWorkerMailer.tasks_due_tomorrow_of(user).deliver_now
      end
    end
  end

  def self.by_case_note_domain_group(cdg)
    cdg_tasks  = cdg.tasks.ids
    incomplete = self.incomplete.ids
    ids        = cdg_tasks + incomplete
    where(id: ids)
  end

  def create_task_history
    TaskHistory.initial(self)
  end

  private

  def push_google_calendar
    return unless GoogleCalendarPush.enabled?
    tenant = Apartment::Tenant.current
    # reload: on CREATE the through-association was cached empty on the new record before
    # set_users fanned the CaseWorkerTask rows (after_save) — a stale read pushes to no one.
    users.reload.each do |user|
      next unless user.calendar_integration? && user.google_refresh_token.present?
      GoogleCalendarPushWorker.perform_async('upsert', tenant, id, user.id, nil)
    end
  end

  def capture_google_push_removals
    @google_push_removals = google_task_events.pluck(:user_id, :google_event_id)
  end

  def push_google_calendar_removals
    return unless GoogleCalendarPush.enabled?
    tenant = Apartment::Tenant.current
    (@google_push_removals || []).each do |user_id, event_id|
      GoogleCalendarPushWorker.perform_async('delete', tenant, nil, user_id, event_id)
    end
  end
end
