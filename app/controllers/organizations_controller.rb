class OrganizationsController < ApplicationController
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
