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
    render :personal
  end
end
