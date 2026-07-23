class AdminController < ApplicationController
  protect_from_forgery with: :exception

  before_action :authenticate_user!
  before_action :notify_user, :set_sidebar_basic_info

  protected

  def notify_user
    @notification = UserNotification.new(current_user)
  end

  def set_sidebar_basic_info
    @client_count  = Client.accessible_by(current_ability).count
    # UX round 3 (B4): the sidebar badge follows the viewer's household scope (matches the
    # @client_count idiom; .distinct — the caseload rule joins through cases).
    @family_count  = Family.accessible_by(current_ability).distinct.count
    @user_count    = User.accessible_by(current_ability).count
    @partner_count = Partner.count
    @agency_count  = Agency.count
    @referral_source_count = ReferralSource.count
  end
end
