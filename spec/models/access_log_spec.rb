# frozen_string_literal: true

require "rails_helper"

# AccessLog model spec. Suite runs every example inside tenant "app"
# (spec_helper before(:suite) create_and_build_tanent + before(:each) switch!),
# so Organization.current.short_name == "app" and the tenant default resolves
# automatically. Mongo is NOT auto-cleaned (DatabaseCleaner is AR-only) ->
# we clean AccessLog ourselves around each example.
RSpec.describe AccessLog, type: :model do
  # unscoped: this spec creates a tenant:"other-org" row; a tenant-scoped
  # delete_all would leave it to pollute later specs' unscoped counts.
  before(:each) { AccessLog.unscoped.delete_all }
  after(:each)  { AccessLog.unscoped.delete_all }

  # Minimal request/controller doubles so we can exercise the helpers without
  # rendering an authenticated AdminController page (known-fragile per briefing).
  def fake_request(overrides = {})
    defaults = {
      request_method: "GET",
      fullpath:       "/clients/42",
      remote_ip:      "203.0.113.7",
      request_id:     "req-abc-123",
      params:         { controller: "clients", action: "show" }
    }
    double("request", defaults.merge(overrides))
  end

  def fake_controller(user:, params: { id: "42" }, request: fake_request)
    double(
      "controller",
      request:         request,
      current_user:    user,
      params:          params,
      controller_name: "clients",
      action_name:     "show"
    )
  end

  describe "tenant isolation (AU-9)" do
    it "defaults tenant to the current organization short_name (\"app\")" do
      log = AccessLog.create!(event_type: "read")
      expect(log.tenant).to eq("app")
    end

    it "scopes queries to the current tenant" do
      AccessLog.create!(event_type: "read")
      # A row planted under a different tenant must be invisible to the default scope.
      AccessLog.collection.insert_one(
        event_type: "read", tenant: "other-org", created_at: Time.current
      )

      expect(AccessLog.count).to eq(1)
      expect(AccessLog.first.tenant).to eq("app")
      expect(AccessLog.unscoped.where(tenant: "other-org").count).to eq(1)
    end
  end

  describe "append-only / WORM (AU-9)" do
    it "raises on update" do
      log = AccessLog.create!(event_type: "read")
      expect { log.update!(action: "index") }.to raise_error(RuntimeError, /append-only/)
    end

    it "raises on destroy" do
      log = AccessLog.create!(event_type: "read")
      expect { log.destroy }.to raise_error(RuntimeError, /append-only/)
    end

    it "permits the sanctioned bulk purge via delete_all (skips callbacks)" do
      AccessLog.create!(event_type: "read")
      expect { AccessLog.delete_all }.not_to raise_error
      expect(AccessLog.count).to eq(0)
    end
  end

  describe ".record_read!" do
    let(:user) { create(:user) }

    it "writes a read row with actor + resource ids (and never contents)" do
      AccessLog.record_read!(fake_controller(user: user))

      log = AccessLog.last
      expect(log).to be_present
      expect(log.event_type).to eq("read")
      expect(log.user_id).to eq(user.id)
      expect(log.user_email).to eq(user.email)        # denormalized actor handle
      expect(log.resource_type).to eq("Client")        # controller_name.classify
      expect(log.resource_id).to eq("42")              # params[:id]
      expect(log.controller).to eq("clients")
      expect(log.action).to eq("show")
      expect(log.http_method).to eq("GET")
      expect(log.path).to eq("/clients/42")
      expect(log.remote_ip).to eq("203.0.113.7")
      expect(log.request_id).to eq("req-abc-123")
    end

    it "handles a nil current_user without raising (user_id/email nil)" do
      expect { AccessLog.record_read!(fake_controller(user: nil)) }.not_to raise_error
      log = AccessLog.last
      expect(log.user_id).to be_nil
      expect(log.user_email).to be_nil
    end

    it "never raises into the request; logs an error if the write blows up" do
      allow(AccessLog).to receive(:create!).and_raise(StandardError, "mongo down")
      expect(Rails.logger).to receive(:error).with(/record_read! failed/)
      expect { AccessLog.record_read!(fake_controller(user: user)) }.not_to raise_error
    end

    it "emits a compact structured JSON audit line to Rails.logger" do
      expect(Rails.logger).to receive(:info) do |line|
        parsed = JSON.parse(line)
        expect(parsed["tag"]).to eq("access_log")
        expect(parsed["event_type"]).to eq("read")
        expect(parsed["resource_type"]).to eq("Client")
        expect(parsed).not_to have_key("name") # content-free
      end
      AccessLog.record_read!(fake_controller(user: user))
    end
  end

  describe ".security_event!" do
    it "writes a login_failure row from a raw request (no user)" do
      req = fake_request(fullpath: "/users/sign_in", params: { controller: "sessions", action: "create" })
      AccessLog.security_event!(event_type: "login_failure", request: req,
                                metadata: { "attempted_email" => "nobody@example.com" })

      log = AccessLog.last
      expect(log.event_type).to eq("login_failure")
      expect(log.user_id).to be_nil
      expect(log.path).to eq("/users/sign_in")
      expect(log.metadata["attempted_email"]).to eq("nobody@example.com")
    end

    it "records the actor when a user is supplied (e.g. account_locked)" do
      user = create(:user)
      AccessLog.security_event!(event_type: "account_locked", request: fake_request, user: user)

      log = AccessLog.last
      expect(log.event_type).to eq("account_locked")
      expect(log.user_id).to eq(user.id)
      expect(log.user_email).to eq(user.email)
    end

    it "never raises into the request on write failure" do
      allow(AccessLog).to receive(:create!).and_raise(StandardError, "mongo down")
      expect(Rails.logger).to receive(:error).with(/security_event! failed/)
      expect {
        AccessLog.security_event!(event_type: "login_failure", request: fake_request)
      }.not_to raise_error
    end
  end
end
