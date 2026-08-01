# Schools batch SCH1 — schools as a first-class surface (owner: "as important as
# households" for the youth flavor). A school IS a partner agency (kind=school,
# seeded by youth:seed_schools); this controller is the browsable front for them.
# Rosters are ALWAYS ability-scoped: a case worker sees only their own caseload's
# youths at a school, managers their team, leadership the org.
class SchoolsController < AdminController
  authorize_resource class: 'Agency'

  def index
    @schools = Agency.where(kind: 'school').order(:name)
    scope = Client.accessible_by(current_ability)
    @youth_counts = AgencyClient.where(agency_id: @schools.select(:id),
                                       client_id: scope.select(:id))
                                .group(:agency_id).distinct.count(:client_id)
  end

  def show
    @school = Agency.where(kind: 'school').find(params[:id])
    @youths = school_youths(@school)
    @active_enrollments = ClientEnrollment.where(client_id: @youths.select(:id), status: 'Active')
                                          .joins(:program_stream)
                                          .group('program_streams.name').count
  end

  # SCH2 — bulk report-card entry: one row per PV-enrolled youth at this school,
  # each non-blank row becomes an Academic Check-in tracking entry with
  # entry_date = the report date (backdatable — the Y2 service-date column).
  def report_cards
    @school = Agency.where(kind: 'school').find(params[:id])
    authorize! :create, ClientEnrollmentTracking
    @rows = aeries_enrollments(@school)
  end

  def create_report_cards
    @school = Agency.where(kind: 'school').find(params[:id])
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

  AERIES_TRACKING = 'Academic Check-in (Aeries)'
  AERIES_PROGRAM = '¡Por Vida!'

  def school_youths(school)
    Client.accessible_by(current_ability)
          .joins(:agency_clients)
          .where(agency_clients: { agency_id: school.id })
          .distinct
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
