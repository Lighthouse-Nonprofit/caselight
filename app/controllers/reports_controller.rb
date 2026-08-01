# Investor UX round (2026-07): the Reports landing page. Reports batch (2026-08):
# the per-flavor report library mounts here — Reports::Registry picks the flavor's
# definitions, the audience tier gates WHICH definitions a role may run, and every
# report's data flows through Client.accessible_by(current_ability) (worker =
# caseload, manager = team, admin/overviewer = org). Sensitivity masking arrives
# pre-resolved (visible_domain_levels / visible_custom_field_ids); output is
# per-viewer and never cached.
class ReportsController < AdminController
  include SensitiveFields

  # can?(:index/:show, :report) — the baseline gate; per-definition tiers in #show.
  authorize_resource class: false

  def index
    @definitions_by_tier = Reports::Registry.visible_to(current_ability)
                                            .group_by(&:audience)
    clients = Client.accessible_by(current_ability)
    @csi_statistics = CsiStatistic.new(clients, visible_levels: visible_domain_levels)
                                  .assessment_domain_score.to_json
    @cases_statistics = CaseStatistic.new(clients).statistic_data.to_json
  end

  def show
    @definition = Reports::Registry.find!(params[:id])
    authorize! Reports::Registry::TIER_ACTIONS.fetch(@definition.audience), :report
    @period = Reports::Period.resolve(@definition, params)
    @report = @definition.build(
      clients: Client.accessible_by(current_ability),
      period: @period,
      visible_domain_levels: visible_domain_levels,
      visible_custom_field_ids: visible_custom_field_ids,
      viewer: current_user
    )
    @period_options = Reports::Period.options_for(@definition)
  end
end
