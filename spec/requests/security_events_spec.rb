# frozen_string_literal: true
require "rails_helper"

# Component B — security events (AU-2 / AC-7) driven through the REAL Warden
# failure path. login_failure / account_locked are exercised via UNAUTHENTICATED
# POST /users/sign_in (the bad-password path goes through Warden -> our hook).
# access_denied is tested separately in spec/controllers/access_denied_spec.rb
# via an anonymous controller that raises into the real rescue_from chain (the
# bare-controller-internals approach does not exist in Rails 7.2).
#
# Test-design notes (per the Phase 3 briefing):
#  - Every example runs in tenant "app" (rails_helper switches there), so the
#    AccessLog tenant default resolves to "app" automatically.
#  - DatabaseCleaner is ActiveRecord-only; Mongo is NOT auto-cleaned, so we
#    AccessLog.delete_all before AND after each example (delete_all skips the
#    append-only callbacks, which is the sanctioned path).
RSpec.describe "Security events (AU-2 / AC-7)", type: :request do
  before(:each) { AccessLog.delete_all }
  after(:each)  { AccessLog.delete_all }

  describe "failed login" do
    it "records a login_failure AccessLog row on a wrong-password sign-in" do
      user = create(:user)

      expect {
        post user_session_path, params: { user: { email: user.email, password: "wrong-password" } }
      }.to change { AccessLog.where(event_type: "login_failure").count }.by(1)

      log = AccessLog.where(event_type: "login_failure").last
      expect(log.tenant).to eq("app")
      expect(log.user_id).to eq(user.id)
      expect(log.user_email).to eq(user.email)
      expect(log.metadata["attempted_email"]).to eq(user.email)
      expect(log.metadata["factor"]).to eq("password")
      # No record CONTENTS are ever stored -- only ids/types/email.
      expect(log.remote_ip).to be_present
    end

    it "records a login_failure even when the email maps to no user" do
      expect {
        post user_session_path, params: { user: { email: "ghost@example.com", password: "whatever" } }
      }.to change { AccessLog.where(event_type: "login_failure").count }.by(1)

      log = AccessLog.where(event_type: "login_failure").last
      expect(log.user_id).to be_nil
      expect(log.metadata["attempted_email"]).to eq("ghost@example.com")
    end
  end

  describe "account lockout" do
    # Devise :lockable locks after maximum_attempts. Set the user one short of
    # the threshold so a single more bad attempt trips the lock -- keeps the spec
    # fast and asserts the lock PATH rather than hammering N requests.
    it "records an account_locked row when a failed login crosses the threshold" do
      user = create(:user)
      threshold = Devise.maximum_attempts
      user.update_column(:failed_attempts, threshold - 1)

      expect {
        post user_session_path, params: { user: { email: user.email, password: "still-wrong" } }
      }.to change { AccessLog.where(event_type: "account_locked").count }.by(1)

      user.reload
      expect(user.access_locked?).to be(true)

      locked = AccessLog.where(event_type: "account_locked").last
      expect(locked.tenant).to eq("app")
      expect(locked.user_id).to eq(user.id)
      expect(locked.user_email).to eq(user.email)

      # The same failed attempt also produces a login_failure row.
      expect(AccessLog.where(event_type: "login_failure").count).to eq(1)
    end

    it "does NOT record account_locked while the user is still below the threshold" do
      user = create(:user)
      user.update_column(:failed_attempts, 0)

      post user_session_path, params: { user: { email: user.email, password: "nope" } }

      expect(AccessLog.where(event_type: "account_locked").count).to eq(0)
      expect(AccessLog.where(event_type: "login_failure").count).to eq(1)
    end
  end
end
