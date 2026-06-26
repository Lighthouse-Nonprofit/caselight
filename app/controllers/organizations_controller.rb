class OrganizationsController < ApplicationController
  # Public tenant landing (#index) + robots.txt (#robots) — no resource to authorize, and #index is the
  # root_url denial target, so it MUST be skip-listed or the Phase-5.6 verify_authorized cutover would
  # loop every denial back through an un-authorized action. Inert until check_authorization is enabled.
  skip_authorization_check

  def index
    @organizations = Organization.order(:created_at)
    redirect_to dashboards_url(subdomain: Organization.current.short_name) if user_signed_in?
  end

  def robots
    robots = File.read(Rails.root + "config/robots/#{Rails.env}.txt")
    # Rails 5.1 deprecated `render text:`; `render plain:` sets a text/plain content type.
    render plain: robots, layout: false
  end
end
