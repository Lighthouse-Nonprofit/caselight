class PasswordsController < Devise::PasswordsController
  # Phase 5.6 (AC-3) allowlist: Devise forgot-password flow is unauthenticated (reset token, not a CanCan
  # resource). No resource to authorize.
  skip_authorization_check

  def user_for_paper_trail
    params[:user][:email] if params[:user] && params[:user][:email]
  end
end
