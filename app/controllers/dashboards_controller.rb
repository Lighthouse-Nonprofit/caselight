class DashboardsController < AdminController
  # Phase 5.6 (AC-3) allowlist (minimal, only: [:index]): authenticated landing dashboard with no
  # addressable resource; its data is ALREADY Client.accessible_by(current_ability)-scoped.
  skip_authorization_check only: [:index]

  def index
    @dashboard = Dashboard.new(Client.accessible_by(current_ability))
  end
end
