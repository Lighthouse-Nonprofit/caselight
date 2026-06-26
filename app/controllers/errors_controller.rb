class ErrorsController < ApplicationController
  layout false
  # Public error pages — no resource to authorize. Must be skip-listed or the Phase-5.6 cutover would
  # raise WHILE rendering an error, masking it with a 500. Inert until check_authorization is enabled.
  skip_authorization_check

  def show
    status_code = params[:code] || 500
    render status_code.to_s, status: status_code
  end
end
