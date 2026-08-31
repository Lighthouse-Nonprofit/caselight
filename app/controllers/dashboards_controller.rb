class DashboardsController < AdminController
  # Phase 5.6 (AC-3) allowlist (minimal, only: [:index]): authenticated landing dashboard with no
  # addressable resource. Both branches are personally scoped — the org view reads
  # accessible_by-style counts in the template, the personal view reads Task.of_user + accessible_by.
  skip_authorization_check only: [:index]

  # Data-task batch C4: admin + strategic overviewer keep the org dashboard (index);
  # everyone else lands on a personal one — their own workload + a 10-day agenda.
  # OCA feedback 2026-08-26 — Araceli: the org dashboard only answered "since the beginning of
  # time", which is useless for a site contact asking "how are we doing this term?". It now takes
  # a PERIOD and an optional COHORT, both plain GET params so the view stays CSP-safe and the URL
  # is shareable.
  #
  # Period presets reuse Reports::Period rather than inventing date maths. The preset list is
  # flavor-shaped: youth thinks in school terms, resettlement in federal fiscal years (mirroring
  # the report registry definitions). Reports::Period.resolve validates the preset against this
  # allowlist, so a tampered `period` param can widen the WINDOW but never the viewer's data
  # scope — every count below is still ability-scoped.
  PeriodDefinition = Struct.new(:presets, keyword_init: true)

  YOUTH_PRESETS         = %i[term sfy_quarter eyc_half calendar_year custom].freeze
  RESETTLEMENT_PRESETS  = %i[ffy ca_sfy calendar_year custom].freeze

  def index
    if current_user.admin? || current_user.strategic_overviewer?
      load_org_dashboard
      return
    end

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

  private

  # Everything the org dashboard renders. Previously these were ~12 inline queries in the view;
  # two of them (Family.count / Client.count) bypassed `accessible_by` entirely, and the
  # per-program and per-household lists were N+1. Both are fixed here.
  def load_org_dashboard
    @period_definition = PeriodDefinition.new(presets: period_presets)
    @period            = Reports::Period.resolve(@period_definition, params)
    @period_options    = Reports::Period.options_for(@period_definition)

    @cohorts       = Cohorts.programs
    @cohort        = @cohorts.find_by(id: params[:cohort_id])
    @cohort_client_ids = cohort_client_ids

    clients = Client.accessible_by(current_ability)
    clients = clients.where(id: @cohort_client_ids) if @cohort

    @clients_total     = clients.count
    @clients_in_period = clients.where(created_at: @period.range.begin.beginning_of_day..@period.range.end.end_of_day).count

    families = Family.accessible_by(current_ability)
    families = families.joins(:clients).where(clients: { id: @cohort_client_ids }).distinct if @cohort
    @families_total = families.count

    @enrollments_active = scoped_enrollments.count
    @programs_offered   = ProgramStream.lifecycle_active.count

    tasks = Task.accessible_by(current_ability)
    @overdue_tasks = tasks.merge(Task.overdue_incomplete).count
    @today_tasks   = tasks.merge(Task.today_incomplete).count

    @checkins_in_period = scoped_trackings.where(entry_date: @period.range).count

    # One grouped query instead of a COUNT per program (was N+1 over every ProgramStream).
    counts_by_program = scoped_enrollments.group(:program_stream_id).distinct.count(:client_id)
    @program_rows = ProgramStream.lifecycle_active.order(:name).map do |ps|
      [ps, counts_by_program.fetch(ps.id, 0)]
    end

    # Same treatment for households (was a COUNT per family). NB: clients belong to families
    # THROUGH cases -- there is no clients.family_id column.
    member_counts = Case.where(family_id: families.select(:id))
                        .where(client_id: Client.accessible_by(current_ability).select(:id))
                        .group(:family_id).distinct.count(:client_id)
    @family_rows = families.order(:name).limit(25).map { |fam| [fam, member_counts.fetch(fam.id, 0)] }

    @recent_activity = scoped_trackings.where(entry_date: @period.range)
                                       .includes(:tracking, client_enrollment: %i[client program_stream])
                                       .order(entry_date: :desc, created_at: :desc)
                                       .limit(8)
  end

  def period_presets
    Rails.application.config.x.flavor == 'youth' ? YOUTH_PRESETS : RESETTLEMENT_PRESETS
  end

  # Cohort membership is the set of clients enrolled in the selected cohort program. nil (not [])
  # when no cohort is picked, so callers can distinguish 'no filter' from 'an empty cohort'.
  def cohort_client_ids
    return nil unless @cohort

    ClientEnrollment.active.for_active_clients
                    .where(program_stream_id: @cohort.id)
                    .distinct.pluck(:client_id)
  end

  def scoped_enrollments
    scope = ClientEnrollment.active.for_active_clients
                            .where(client_id: Client.accessible_by(current_ability).select(:id))
    scope = scope.where(client_id: @cohort_client_ids) if @cohort
    scope
  end

  def scoped_trackings
    scope = ClientEnrollmentTracking.joins(client_enrollment: :client)
                                    .where(clients: { id: Client.accessible_by(current_ability).select(:id) })
    scope = scope.where(client_enrollments: { program_stream_id: @cohort.id }) if @cohort
    scope
  end
end
