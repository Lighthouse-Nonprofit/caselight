# UX round 3 (B3) — household alerts (the family hub's Alerts tab). Resolve-not-delete:
# no destroy route; resolving stamps who/when and the row remains as the audit trail.
class FamilyAlertsController < AdminController
  include AccessAudit
  include SensitiveFields # the family header's Forms chip reads visible_custom_field_ids_for

  prepend_before_action :set_family
  load_and_authorize_resource through: :family

  def index
    @active_alerts   = @family_alerts.active.most_recents
    @resolved_alerts = @family_alerts.resolved.most_recents.page(params[:page]).per(10)
  end

  def new
  end

  def create
    @family_alert.created_by = current_user
    if @family_alert.save
      redirect_to family_family_alerts_path(@family), notice: t('.successfully_created')
    else
      render :new
    end
  end

  def edit
  end

  def update
    if @family_alert.update(family_alert_params)
      redirect_to family_family_alerts_path(@family), notice: t('.successfully_updated')
    else
      render :edit
    end
  end

  def resolve
    authorize! :update, @family_alert
    @family_alert.resolve!(current_user)
    redirect_to family_family_alerts_path(@family), notice: t('.resolved')
  end

  private

  def set_family
    @family = Family.accessible_by(current_ability).find(params[:family_id])
  end

  def family_alert_params
    params.require(:family_alert).permit(:severity, :title, :body)
  end
end
