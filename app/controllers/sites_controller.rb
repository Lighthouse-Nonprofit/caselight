# Sites — the youth-flavor list of program-DELIVERY locations (kind=site agencies),
# distinct from Schools (kind=school = the school of ATTENDANCE, with the hub/Aeries).
# A campus is both a school and a site (same name, two kinds); a Site can also be a
# community location with no school. LOCKED to the youth flavor by a route constraint
# (config/routes.rb), mirroring SchoolsController.
class SitesController < AdminController
  authorize_resource class: 'Agency'

  before_action :find_site, only: %i[update destroy]

  def index
    scope    = Agency.where(kind: 'site')
    @sites   = scope.order(:name).page(params[:page]).per(20)
    @results = scope.count
  end

  def create
    @site = Agency.new(site_params.merge(kind: 'site'))
    if @site.save
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
