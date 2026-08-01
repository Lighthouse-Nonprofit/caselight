# Schools batch SCH1 + HUB1 — schools as a first-class youth surface, now a
# real hub: Overview / Roster / Cohorts tabs (server-rendered pages, the client
# hub pattern) plus the entry surfaces (report cards; roll call in HUB2).
# Rosters are ALWAYS ability-scoped: a case worker sees only their own
# caseload's youths at a school, managers their team, leadership the org.
class SchoolsController < AdminController
  authorize_resource class: 'Agency'

  before_action :set_school, except: [:index]
  before_action :set_hub, except: [:index]

  def index
    @schools = Agency.where(kind: 'school').order(:name)
    scope = Client.accessible_by(current_ability)
    @youth_counts = AgencyClient.where(agency_id: @schools.select(:id),
                                       client_id: scope.select(:id))
                                .group(:agency_id).distinct.count(:client_id)
    # Card meta — batched COUNT/pluck only (no decrypts on the landing page).
    program = ProgramStream.find_by(name: AERIES_PROGRAM)
    @pv_counts = if program
                   ClientEnrollment.where(status: 'Active', program_stream_id: program.id,
                                          client_id: scope.select(:id))
                                   .joins(client: :agency_clients)
                                   .where(agency_clients: { agency_id: @schools.select(:id) })
                                   .group('agency_clients.agency_id').distinct.count(:client_id)
                 else
                   {}
                 end
    @cohort_tags = ClientEnrollment
                   .joins(:program_stream, client: :agency_clients)
                   .where(program_streams: { id: Cohorts.programs.reorder(nil).select(:id) },
                          agency_clients: { agency_id: @schools.select(:id) },
                          client_id: scope.select(:id))
                   .distinct.pluck('agency_clients.agency_id', 'program_streams.name')
                   .group_by(&:first)
                   .transform_values { |pairs| pairs.map(&:last).uniq.sort }
  end

  # Overview tab: stat tiles + info grid + recent activity.
  def show
    youth_ids = school_youths(@school).ids
    @active_enrollments = ClientEnrollment.where(client_id: youth_ids, status: 'Active')
                                          .joins(:program_stream)
                                          .group('program_streams.name').count
    @entries_this_month = school_entries(youth_ids)
                          .where(entry_date: Time.zone.today.beginning_of_month..).count
    @cohort_youth_count = @hub_cards.cards.sum(&:enrolled)
    @recent_entries = school_entries(youth_ids)
                      .includes(:tracking, client_enrollment: %i[client program_stream])
                      .order(entry_date: :desc, created_at: :desc).limit(8)
  end

  def roster
    @rows = Schools::Roster.new(youths: school_youths(@school)).rows
  end

  def cohorts
    @cards = @hub_cards.cards
  end

  # HUB2 (SCH2 origin) — bulk report-card entry; POST semantics unchanged.
  # GET gains prefill PLACEHOLDERS from each enrollment's latest Aeries entry
  # (placeholder never value — blank row still means "save nothing").
  def report_cards
    authorize! :create, ClientEnrollmentTracking
    @rows = aeries_enrollments(@school)
    @prefills = latest_aeries_props_by_client(@rows)
  end

  # HUB2 — cohort roll call: one session date + number, one tap per youth.
  def roll_call
    authorize! :create, ClientEnrollmentTracking
    @program = Cohorts.programs.find(params.require(:program_stream_id))
    @tracking = @program.trackings.find_by!(name: Cohorts::SESSION_TRACKING)
    @rows = @hub_cards.roster_for(@program)
    @total_sessions = Cohorts.total_sessions(@program.name)
  end

  def create_roll_call
    authorize! :create, ClientEnrollmentTracking
    program = Cohorts.programs.find(params.require(:program_stream_id))
    tracking = program.trackings.find_by!(name: Cohorts::SESSION_TRACKING)
    session_date = begin
      Date.iso8601(params.require(:session_date))
    rescue ArgumentError, Date::Error
      return redirect_to roll_call_school_path(@school, program_stream_id: program.id),
                         alert: t('schools.roll_call.bad_date')
    end
    session_number = params[:session_number].to_s
    unless (1..Cohorts.total_sessions(program.name)).cover?(session_number.to_i)
      return redirect_to roll_call_school_path(@school, program_stream_id: program.id),
                         alert: t('schools.roll_call.bad_session')
    end

    enrollments = @hub_cards.roster_for(program).index_by { |e| e.client_id.to_s }
    taken = ClientEnrollmentTracking.where(client_enrollment_id: enrollments.values.map(&:id),
                                           tracking_id: tracking.id, entry_date: session_date)
                                    .pluck(:client_enrollment_id).to_set
    created = skipped = 0
    params.fetch(:roll, {}).each do |client_id, row|
      enrollment = enrollments[client_id.to_s] or next # foreign ids ignored
      attendance = row[:attendance].to_s
      next unless %w[Present Absent Excused].include?(attendance) # unset row = no entry
      if taken.include?(enrollment.id) # DEDUPE (read-then-write; pilot-scale ok)
        skipped += 1
        next
      end
      values = { 'Session Number' => session_number, 'Attendance' => attendance,
                 'Session Notes' => row[:notes] }
               .transform_values { |v| v.to_s.strip }.reject { |_k, v| v.blank? }
      entry = ClientEnrollmentTracking.new(client_enrollment_id: enrollment.id,
                                           tracking_id: tracking.id,
                                           entry_date: session_date, properties: values)
      created += 1 if entry.save
    end
    notice = t('schools.roll_call.saved', count: created)
    notice += " #{t('schools.roll_call.skipped', count: skipped)}" if skipped.positive?
    redirect_to cohorts_school_path(@school), notice: notice
  end

  def create_report_cards
    authorize! :create, ClientEnrollmentTracking
    report_date = begin
      Date.iso8601(params.require(:report_date))
    rescue ArgumentError, Date::Error
      return redirect_to report_cards_school_path(@school), alert: t('schools.report_cards.bad_date')
    end

    enrollments = aeries_enrollments(@school).index_by { |e| e.client_id.to_s }
    created = 0
    params.fetch(:report_cards, {}).each do |client_id, row|
      enrollment = enrollments[client_id.to_s] or next
      values = {
        'GPA (x100, e.g. 275 = 2.75)' => row[:gpa],
        'Credits Earned (cumulative)' => row[:credits],
        'A-G On Track' => row[:ag],
        'School-Day Attendance % (this period)' => row[:attendance],
        'Discipline Incidents (this period)' => row[:discipline],
        'Concerns / IEP-SST Notes' => row[:notes]
      }.transform_values { |v| v.to_s.strip }.reject { |_k, v| v.blank? }
      next if values.empty? # blank row = no entry

      tracking = enrollment.program_stream.trackings.find_by(name: AERIES_TRACKING)
      entry = ClientEnrollmentTracking.new(client_enrollment_id: enrollment.id,
                                           tracking_id: tracking.id,
                                           entry_date: report_date, properties: values)
      created += 1 if entry.save
    end
    redirect_to school_path(@school),
                notice: t('schools.report_cards.created', count: created)
  end

  private

  AERIES_TRACKING = Schools::Roster::AERIES_TRACKING
  AERIES_PROGRAM = Schools::Roster::AERIES_PROGRAM

  def set_school
    @school = Agency.where(kind: 'school').find(params[:id])
  end

  # Header meta + tab chips — COUNT/sidecar-only, no decrypts (entry pages
  # must stay snappy).
  def set_hub
    youth_ids = school_youths(@school).ids
    @hub_youth_count = youth_ids.size
    @hub_pv_count = begin
      program = ProgramStream.find_by(name: AERIES_PROGRAM)
      program ? ClientEnrollment.where(client_id: youth_ids, status: 'Active',
                                       program_stream_id: program.id).count : 0
    end
    @hub_cards = Schools::CohortCards.new(youth_ids: youth_ids)
  end

  def school_youths(school)
    Client.accessible_by(current_ability)
          .joins(:agency_clients)
          .where(agency_clients: { agency_id: school.id })
          .distinct
  end

  def school_entries(youth_ids)
    ClientEnrollmentTracking
      .joins(:client_enrollment)
      .where(client_enrollments: { client_id: youth_ids })
  end

  # Latest Aeries properties per client for placeholder prefill — the bounded
  # HUB1 pattern: DISTINCT ON id-list first, one DecryptedScan pass.
  def latest_aeries_props_by_client(enrollments)
    ids = Schools::Roster.latest_aeries_ids(enrollments.map(&:id))
    client_by_enrollment = enrollments.to_h { |e| [e.id, e.client_id] }
    prefills = {}
    Reports::DecryptedScan.each(ClientEnrollmentTracking.where(id: ids)) do |record, props|
      client_id = client_by_enrollment[record.client_enrollment_id] or next
      prefills[client_id] = props
    end
    prefills
  end

  # Active ¡Por Vida! enrollments (the program carrying the Aeries tracking)
  # for this school's ability-scoped youths.
  def aeries_enrollments(school)
    program = ProgramStream.find_by(name: AERIES_PROGRAM)
    return [] if program.nil? || program.trackings.find_by(name: AERIES_TRACKING).nil?
    ClientEnrollment.where(client_id: school_youths(school).select(:id),
                           program_stream_id: program.id, status: 'Active')
                    .includes(:client, program_stream: :trackings)
                    .sort_by { |e| e.client.name.to_s }
  end
end
