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
    @youths = Client.accessible_by(current_ability)
                    .joins(:agency_clients)
                    .where(agency_clients: { agency_id: @school.id })
                    .distinct
    @active_enrollments = ClientEnrollment.where(client_id: @youths.select(:id), status: 'Active')
                                          .joins(:program_stream)
                                          .group('program_streams.name').count
  end
end
