# frozen_string_literal: true

require "rails_helper"

# AccessAudit concern spec. Per the briefing, rendering an authenticated
# AdminController page in a request spec is fragile -> we test the concern in
# isolation with an ANONYMOUS controller that includes AccessAudit and exposes
# trivial show/index actions returning head(:ok). Mongo isn't auto-cleaned.
RSpec.describe AccessAudit, type: :controller do
  # Anonymous controller. controller_name is "anonymous" by default, so we stub
  # controller_name to "clients" to assert the derived resource_type.
  controller(ApplicationController) do
    include AccessAudit
    # Phase 5.6 (AC-3): ApplicationController now runs the AuthorizationShadow after_action, which would
    # log an extra 'authorization_shadow' AccessLog row for this default-open anonymous fixture and skew
    # the read-logging counts below. Real controllers authorize or skip; mirror that so this concern
    # spec measures ONLY AccessAudit's read rows.
    skip_authorization_check

    def show
      head :ok
    end

    def index
      head :ok
    end
  end

  before do
    AccessLog.delete_all
    # Route the trivial actions for this anonymous controller.
    routes.draw do
      get "show"  => "anonymous#show"
      get "index" => "anonymous#index"
    end
    # The concern derives resource_type from controller_name; pin it to "clients".
    allow(controller).to receive(:controller_name).and_return("clients")
  end

  after { AccessLog.delete_all }

  let(:user) { create(:user) }

  context "when a user is signed in and the response is 2xx" do
    before { allow(controller).to receive(:current_user).and_return(user) }

    it "writes a read row with the right resource_type/resource_id/user on show" do
      get :show, params: { id: "99" }

      expect(response).to have_http_status(:ok)
      log = AccessLog.last
      expect(log).to be_present
      expect(log.event_type).to eq("read")
      expect(log.resource_type).to eq("Client")  # controller_name.classify
      expect(log.resource_id).to eq("99")         # params[:id]
      expect(log.action).to eq("show")
      expect(log.user_id).to eq(user.id)
      expect(log.user_email).to eq(user.email)
    end

    it "writes a collection read row on index (no resource_id)" do
      get :index

      log = AccessLog.last
      expect(log).to be_present
      expect(log.action).to eq("index")
      expect(log.resource_id).to be_nil
    end
  end

  context "guards" do
    it "does not log when there is no current_user" do
      allow(controller).to receive(:current_user).and_return(nil)
      get :show, params: { id: "99" }
      expect(AccessLog.count).to eq(0)
    end

    it "does not log when access logging is explicitly disabled via config flag" do
      allow(controller).to receive(:current_user).and_return(user)
      allow(Rails.application.config.x).to receive(:access_logging_enabled).and_return(false)
      get :show, params: { id: "99" }
      expect(AccessLog.count).to eq(0)
    end

    it "STILL logs (fails safe) when the flag is unset/nil" do
      allow(controller).to receive(:current_user).and_return(user)
      allow(Rails.application.config.x).to receive(:access_logging_enabled).and_return(nil)
      get :show, params: { id: "99" }
      expect(AccessLog.count).to eq(1)
    end
  end

  context "resilience" do
    before { allow(controller).to receive(:current_user).and_return(user) }

    it "cannot 500 the action if logging raises" do
      allow(AccessLog).to receive(:record_read!).and_raise(StandardError, "boom")
      expect(Rails.logger).to receive(:error).with(/record_access_read failed/)

      get :show, params: { id: "99" }

      # The action itself still succeeds; auditing failure is swallowed.
      expect(response).to have_http_status(:ok)
    end
  end
end
