class OrganizationsController < ApplicationController
  # Public tenant landing (#index) + robots.txt (#robots) — no resource to authorize, and #index is the
  # root_url denial target, so it MUST be skip-listed or the Phase-5.6 verify_authorized cutover would
  # loop every denial back through an un-authorized action. Inert until check_authorization is enabled.
  skip_authorization_check

  def index
    return redirect_to dashboards_url(subdomain: Organization.current.short_name) if user_signed_in? && Organization.current

    # A host that NAMES a tenant belongs to that org, so it gets its own sign-in page — never a
    # picker listing every organization on the box. Organization is an Apartment *excluded* model
    # (config/initializers/apartment.rb), so this list always reads the public schema no matter
    # which tenant the elevator selected: without this redirect, staff at org-a.example.org would
    # see org-b's name on their landing page. The picker survives only for a host that resolves no
    # tenant (the bare domain), which is where choosing between orgs is the actual point.
    return redirect_to new_user_session_path if host_tenant.present?

    @organizations = Organization.order(:created_at)
  end

  def robots
    robots = File.read(Rails.root + "config/robots/#{Rails.env}.txt")
    # Rails 5.1 deprecated `render text:`; `render plain:` sets a text/plain content type.
    render plain: robots, layout: false
  end

  private

  # The tenant this REQUEST HOST names, asked of the elevator itself so the answer matches what
  # the middleware did (subdomain parsing differs between PublicSuffix and tld_length, and the
  # .localhost override only exists on our subclass). Deliberately not Apartment::Tenant.current:
  # the test suite elevates a tenant by hand on a host that names none, and a picker request on
  # the bare domain would otherwise look tenanted.
  def host_tenant
    name = Apartment::Elevators::SubdomainWithLocalhost.new(nil).parse_tenant_name(request)
    name if name.present? && Organization.exists?(short_name: name)
  end
end
