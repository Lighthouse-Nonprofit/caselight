class ErrorsController < ApplicationController
  layout false
  # Public error pages — no resource to authorize. Must be skip-listed or the Phase-5.6 cutover would
  # raise WHILE rendering an error, masking it with a 500. Inert until check_authorization is enabled.
  skip_authorization_check

  # routes.rb maps exactly /404 and /500 here (config.exceptions_app = routes). Branch on the code
  # instead of rendering `params[:code]` so no request value ever names a template (Brakeman
  # "Dynamic Render Path", baselined since Phase 7 -- now gone).
  # Only HTML templates exist. A request whose format is json/xml/gif/yaml/zip (scanner probes like
  # /phpinfo.php.json, or /404.gif) used to raise ActionView::MissingTemplate INSIDE the error page,
  # turning a 404 into a 500 (then a 409 via TenantBoundary). Always render the HTML page.
  def show
    if params[:code].to_s == '404'
      render '404', status: :not_found, formats: [:html]
    else
      render '500', status: :internal_server_error, formats: [:html]
    end
  end
end
