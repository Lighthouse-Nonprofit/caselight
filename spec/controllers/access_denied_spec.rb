# frozen_string_literal: true
require "rails_helper"

# Component B — access_denied security event (AU-2 / AC-3), driven through the
# REAL ApplicationController rescue_from chain via an anonymous controller that
# raises the authorization errors. This exercises the exact production seam
# Component B edits (the two rescue_from blocks) and avoids both the fragile
# authenticated-AdminController render AND the non-existent Rails internals
# (set_request!/rescue_handler_hash) the original draft used.
#
# Requires Devise::Test::ControllerHelpers for :controller specs. If the suite's
# rails_helper only wires Devise::Test::IntegrationHelpers (request specs), add:
#   config.include Devise::Test::ControllerHelpers, type: :controller
# to spec/rails_helper.rb. (We stub current_user directly below so the spec also
# passes without sign_in, but the include is the conventional setup.)
RSpec.describe "access_denied security event", type: :controller do
  controller(ApplicationController) do
    def explode_cancan
      raise CanCan::AccessDenied.new("You are not authorized to access this page.")
    end

    def explode_pundit
      raise Pundit::NotAuthorizedError, "not allowed"
    end
  end

  let(:user) { create(:user) }

  before do
    AccessLog.delete_all
    routes.draw do
      get "explode_cancan" => "anonymous#explode_cancan"
      get "explode_pundit" => "anonymous#explode_pundit"
    end
    allow(controller).to receive(:current_user).and_return(user)
  end

  after { AccessLog.delete_all }

  it "records an access_denied row and redirects to root on CanCan::AccessDenied" do
    expect { get :explode_cancan }
      .to change { AccessLog.where(event_type: "access_denied").count }.by(1)

    log = AccessLog.where(event_type: "access_denied").last
    expect(log.tenant).to eq("app")
    expect(log.user_id).to eq(user.id)
    expect(log.user_email).to eq(user.email)
    expect(log.metadata["source"]).to eq("cancan")
    expect(log.metadata["reason"]).to eq("You are not authorized to access this page.")
    expect(response).to redirect_to(root_url)
  end

  it "records an access_denied row on Pundit::NotAuthorizedError" do
    expect { get :explode_pundit }
      .to change { AccessLog.where(event_type: "access_denied").count }.by(1)

    log = AccessLog.where(event_type: "access_denied").last
    expect(log.metadata["source"]).to eq("pundit")
    expect(response).to redirect_to(root_url)
  end
end
