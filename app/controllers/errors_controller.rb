class ErrorsController < ApplicationController
  layout false
  # Public error pages — no resource to authorize. Must be skip-listed or the Phase-5.6 cutover would
  # raise WHILE rendering an error, masking it with a 500. Inert until check_authorization is enabled.
  skip_authorization_check

  def show
    status_code = params[:code] || 500
    # Only HTML templates exist. A request whose format is json/xml/gif/yaml/zip (scanner probes like
    # /phpinfo.php.json, or /404.gif) used to raise ActionView::MissingTemplate INSIDE the error page,
    # turning a 404 into a 500 (then a 409 via TenantBoundary). Always render the HTML page.
    render status_code.to_s, status: status_code, formats: [:html]
  end
end
