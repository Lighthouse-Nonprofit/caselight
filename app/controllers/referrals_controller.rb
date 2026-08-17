# PR 4 — the org-wide "referrals OUT" roll-up. Read-only: creation/edit live on the client hub
# (Client::ReferralsController). The list is bounded to the viewer's accessible clients, so a
# case worker sees only their caseload's outbound referrals; admin/overviewer see the org.
class ReferralsController < AdminController
  authorize_resource

  def index
    scope = Referral.where(client_id: Client.accessible_by(current_ability).select(:id))
                    .includes(:client, :user)
    scope = scope.where(status: params[:status]) if params[:status].present? && Referral::STATUSES.include?(params[:status])
    @results   = scope.count
    @referrals = scope.recent.page(params[:page]).per(25)
  end
end
