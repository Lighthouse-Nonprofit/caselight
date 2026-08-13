# Schools — a first-class youth-flavor surface (kind=school agencies), LOCKED to
# that flavor by a route constraint (config/routes.rb). Structure:
#   index                        card grid of schools
#   show / roster / cohorts      the hub tabs (Overview / Roster / Cohorts)
#   cohort                       ONE cohort instance = program × school × term:
#                                its sessions and its roster
#   report_cards                 the report cards ALREADY on file (editable records)
#   new_report_cards / create    batch entry for a report date
#   roll_call / create_roll_call one-tap attendance for a cohort session
# Every roster flows through Client.accessible_by(current_ability); write actions
# additionally authorize :create, ClientEnrollmentTracking.
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

  # Overview tab.
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
    # S3: schools track EDUCATION, not program delivery — programs are hosted by
    # delivery Sites now. The Overview surfaces the youths' actual "Active
    # enrollments" mix (below), not a static agency↔program host list.
  end

  def roster
    @rows = Schools::Roster.new(youths: school_youths(@school)).rows
  end

  def cohorts
    @cards = @hub_cards.cards
  end

  # S4 — one cohort INSTANCE (program × this school × current term): the sessions
  # that make it up and the roster that attends them.
  def cohort
    @program = Cohorts.programs.find(params[:program_stream_id])
    @instance = Schools::CohortInstance.new(program: @program, school: @school,
                                            enrollments: @hub_cards.roster_for(@program),
                                            term_label: @hub_cards.term_label)
  end

  # S3 — report cards ALREADY on file for this school (editable records), newest
  # first. "New report cards" opens the batch grid.
  def report_cards
    authorize! :create, ClientEnrollmentTracking
    @entries = Schools::ReportCards.new(enrollments: aeries_enrollments(@school)).recent
  end

  def new_report_cards
    authorize! :create, ClientEnrollmentTracking
    @rows = aeries_enrollments(@school)
    @prefills = Schools::ReportCards.new(enrollments: @rows).latest_props_by_client
  end

  def create_report_cards
    authorize! :create, ClientEnrollmentTracking
    # params.require would raise ParameterMissing (a 400) on an EMPTY field —
    # a blank date is user error, so it gets the flash like any other bad date.
    report_date = parse_date(params[:report_date])
    if report_date.nil?
      return redirect_to new_report_cards_school_path(@school), alert: t('schools.report_cards.bad_date')
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
    # land on the INDEX so what was just saved is visible and editable
    redirect_to report_cards_school_path(@school),
                notice: t('schools.report_cards.created', count: created)
  end

  def roll_call
    authorize! :create, ClientEnrollmentTracking
    @program = Cohorts.programs.find(params.require(:program_stream_id))
    @tracking = @program.trackings.find_by!(name: Cohorts::SESSION_TRACKING)
    @rows = @hub_cards.roster_for(@program)
    @total_sessions = Cohorts.total_sessions(@program.name)
    @session_number = params[:session_number].presence
    @session_date = params[:session_date].presence
  end

  def create_roll_call
    authorize! :create, ClientEnrollmentTracking
    program = Cohorts.programs.find(params.require(:program_stream_id))
    tracking = program.trackings.find_by!(name: Cohorts::SESSION_TRACKING)
    session_date = parse_date(params[:session_date])
    if session_date.nil?
      return redirect_to roll_call_school_path(@school, program_stream_id: program.id),
                         alert: t('schools.roll_call.bad_date')
    end
    session_number = params[:session_number].to_s
    unless (1..Cohorts.total_sessions(program.name)).cover?(session_number.to_i)
      return redirect_to roll_call_school_path(@school, program_stream_id: program.id),
                         alert: t('schools.roll_call.bad_session')
    end

    enrollments = @hub_cards.roster_for(program).index_by { |e| e.client_id.to_s }
    # DEDUPE on (enrollment, tracking, date, SESSION NUMBER): two sessions can
    # legitimately be held on one day (a make-up circle), and the same session
    # can be re-entered on a corrected date — keying on the date alone would
    # silently collapse the first and double-count the second. Session numbers
    # live in encrypted properties, so the sidecar answers the "which session"
    # half of the key.
    same_date = ClientEnrollmentTracking.where(client_enrollment_id: enrollments.values.map(&:id),
                                               tracking_id: tracking.id, entry_date: session_date)
    same_session_ids = Reports::ValueCounts.owner_ids(owner_scope: same_date,
                                                     field_label: 'Session Number',
                                                     value: session_number)
    # An entry on that date carrying NO session number (imported, or logged
    # before session numbers were captured) most likely IS this session — block
    # it too, so re-running a roll call can never double-log.
    numbered_ids = ClientEnrollmentTrackingSearchEntry
                   .where(field_label: 'Session Number',
                          client_enrollment_tracking_id: same_date.select(:id))
                   .distinct.pluck(:client_enrollment_tracking_id)
    unnumbered_ids = same_date.where.not(id: numbered_ids).pluck(:id)
    taken = ClientEnrollmentTracking.where(id: same_session_ids + unnumbered_ids)
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
    redirect_to cohort_school_path(@school, program_stream_id: program.id), notice: notice
  end

  private

  AERIES_TRACKING = Schools::Roster::AERIES_TRACKING
  AERIES_PROGRAM = Schools::Roster::AERIES_PROGRAM

  def set_school
    @school = Agency.where(kind: 'school').find(params[:id])
  end

  def parse_date(value)
    Date.iso8601(value.to_s)
  rescue ArgumentError, TypeError, Date::Error
    nil
  end

  # Header meta + tab chips — COUNT/sidecar-only, no decrypts.
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

  # Active ¡Por Vida! enrollments (the program carrying the Aeries tracking) for
  # this school's ability-scoped youths.
  def aeries_enrollments(school)
    program = ProgramStream.find_by(name: AERIES_PROGRAM)
    return [] if program.nil? || program.trackings.find_by(name: AERIES_TRACKING).nil?
    ClientEnrollment.where(client_id: school_youths(school).select(:id),
                           program_stream_id: program.id, status: 'Active')
                    .includes(:client, program_stream: :trackings)
                    .sort_by { |e| e.client.name.to_s }
  end
end
