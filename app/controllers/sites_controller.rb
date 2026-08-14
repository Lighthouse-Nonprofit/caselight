# Sites — the youth-flavor list of program-DELIVERY locations (kind=site agencies),
# distinct from Schools (kind=school = the school of ATTENDANCE, with the hub/Aeries).
# A campus is both a school and a site (same name, two kinds); a Site can also be a
# community location with no school. LOCKED to the youth flavor by a route constraint
# (config/routes.rb), mirroring SchoolsController.
class SitesController < AdminController
  authorize_resource class: 'Agency'

  before_action :find_site, only: %i[show update destroy]

  def index
    scope    = Agency.where(kind: 'site')
    @sites   = scope.order(:name).page(params[:page]).per(20)
    @results = scope.count
    # which sites are also schools (campuses), and how many programs each hosts —
    # computed once to keep the list clickable + labelled without N+1s.
    @school_twins  = Agency.where(kind: 'school').index_by { |a| a.name.to_s.downcase }
    @program_counts = AgencyProgramStream.where(agency_id: @sites.map(&:id)).group(:agency_id).count
  end

  # The delivery-location page: the programs hosted here, the youth actually being
  # served here (via the enrollment's 'Site' field), and a link to the school twin
  # when this campus is also a school.
  def show
    @programs = @site.program_streams.order(:name)
    active = ClientEnrollment.where(client_id: Client.accessible_by(current_ability).select(:id),
                                    status: 'Active')
    site_enrollment_ids = Reports::ValueCounts.owner_ids(owner_scope: active,
                                                         field_label: 'Site', value: @site.name)
    site_enrollments = ClientEnrollment.where(id: site_enrollment_ids).joins(:program_stream)
    @youth_count    = site_enrollments.distinct.count(:client_id)
    @enrollment_mix = site_enrollments.group('program_streams.name').count
    @school_twin    = @site.campus_twin
  end

  def create
    @site = Agency.new(site_params.merge(kind: 'site'))
    if @site.save
      @site.ensure_campus_twin! if params[:also_school] == '1' # make it a campus
      redirect_to sites_path, notice: t('.successfully_created')
    else
      redirect_to sites_path, alert: t('.failed_create')
    end
  end

  def update
    if @site.update(site_params)
      redirect_to sites_path, notice: t('.successfully_updated')
    else
      redirect_to sites_path, alert: t('.failed_update')
    end
  end

  def destroy
    # kind=site agencies carry no AgencyClient links (that's a school concept), but
    # guard anyway — never orphan a link.
    if @site.clients.present?
      redirect_to sites_path, alert: t('.failed_delete')
    else
      @site.destroy
      redirect_to sites_path, notice: t('.successfully_deleted')
    end
  end

  private

  def site_params
    params.require(:agency).permit(:name, :description)
  end

  def find_site
    @site = Agency.where(kind: 'site').find(params[:id])
  end
end
