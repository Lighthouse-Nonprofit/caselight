class DashboardsController < AdminController
  # Phase 5.6 (AC-3) allowlist (minimal, only: [:index]): authenticated landing dashboard with no
  # addressable resource. Both branches are personally scoped — the org view reads
  # accessible_by-style counts in the template, the personal view reads Task.of_user + accessible_by.
  skip_authorization_check only: [:index]

  # Data-task batch C4: admin + strategic overviewer keep the org dashboard (index);
  # everyone else lands on a personal one — their own workload + a 10-day agenda.
  def index
    return if current_user.admin? || current_user.strategic_overviewer?

    my_tasks        = Task.incomplete.of_user(current_user)
    @overdue_count  = my_tasks.overdue.count
    @today_count    = my_tasks.today.count
    @week_count     = my_tasks.where(completion_date: (Time.zone.today + 1)..(Time.zone.today + 7)).count
    @caseload_count = Client.accessible_by(current_ability).count

    # The 7-day agenda (server-rendered — no FullCalendar on the dashboard): every day
    # gets a row, populated or not, so an empty week still reads as a structured schedule.
    # All-day tasks lead each day; timed ones follow in clock order.
    @week_days     = (Time.zone.today..(Time.zone.today + 6)).to_a
    @agenda_by_day = my_tasks.where(completion_date: @week_days.first..@week_days.last)
                             .includes(:client, :domain)
                             .sort_by { |t| [t.timed? ? 1 : 0, t.start_time.to_s] }
                             .group_by(&:completion_date)
    render :personal
  end
end
