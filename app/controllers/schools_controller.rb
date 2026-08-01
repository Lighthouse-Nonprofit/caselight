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
  def report_cards
    authorize! :create, ClientEnrollmentTracking
    @rows = aeries_enrollments(@school)
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
