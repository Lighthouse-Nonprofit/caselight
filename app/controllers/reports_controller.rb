class ReportsController < AdminController
  include SensitiveFields # visible_domain_levels — mask restricted/emergency domains in the CSI chart

  # Investor UX round (2026-07): the Reports landing page — the CSI-domain + case-statistics
  # charts moved here off clients#index (where they hid behind an admin-only toggle), plus links
  # to the data tools. This page is the mount point for per-flavor reporting.
  #
  # authorize_resource class: false => can?(:index, :report). Admin passes via `manage :all`,
  # strategic overviewer via `read :all`; every other role has no :report rule -> AccessDenied
  # (values-free access_denied audit + redirect, the app-wide rescue).
  authorize_resource class: false

  def index
    clients = Client.accessible_by(current_ability)
    @csi_statistics   = CsiStatistic.new(clients, visible_levels: visible_domain_levels).assessment_domain_score.to_json
    @cases_statistics = CaseStatistic.new(clients).statistic_data.to_json
  end
end
