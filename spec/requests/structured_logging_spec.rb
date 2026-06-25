require 'rails_helper'

# Phase 3 — structured request logging (FedRAMP AU-3). ApplicationController#append_info_to_payload
# tags every request's process_action instrumentation with the audit context (request id, user, tenant,
# source IP) that lograge then emits as JSON. Asserted by capturing the instrumentation payload directly
# (lograge's formatter is disabled in test).
RSpec.describe 'Structured request logging (audit tags)', type: :request do
  it 'tags the request log payload with request_id, tenant, and remote_ip' do
    captured = nil
    subscriber = ActiveSupport::Notifications.subscribe('process_action.action_controller') do |*args|
      captured = ActiveSupport::Notifications::Event.new(*args).payload
    end

    get '/users/sign_in'

    ActiveSupport::Notifications.unsubscribe(subscriber)
    expect(captured).to be_present
    expect(captured[:request_id]).to be_present
    expect(captured[:remote_ip]).to be_present
    expect(captured).to have_key(:tenant)   # present (may be the default schema when unauthenticated)
    expect(captured).to have_key(:user_id)  # nil when not signed in, but the audit key is always set
  end
end
