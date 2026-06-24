# Phase 2 (auth hardening) — Rack::Attack brute-force throttling regression spec.
# Maps: FedRAMP AC-7 (unsuccessful-logon attempts), SC-5 (DoS protection).
RSpec.describe 'Brute-force throttling (Rack::Attack)', type: :request do
  around do |example|
    Rack::Attack.enabled = true
    Rack::Attack.cache.store.clear
    example.run
    Rack::Attack.cache.store.clear
    Rack::Attack.enabled = false
  end

  it 'throttles repeated login attempts from one IP with HTTP 429' do
    statuses = Array.new(12) do
      post '/users/sign_in', params: { user: { email: 'attacker@example.test', password: 'wrong' } }
      response.status
    end
    # Limit is 10/min, so the tail of a 12-request burst must be throttled.
    expect(statuses).to include(429)
    expect(statuses.last).to eq(429)
  end

  it 'does not throttle a single normal login attempt' do
    post '/users/sign_in', params: { user: { email: 'user@example.test', password: 'wrong' } }
    expect(response.status).not_to eq(429)
  end
end
