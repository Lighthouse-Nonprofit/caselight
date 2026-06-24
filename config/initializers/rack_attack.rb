# Rack::Attack — brute-force / rate-limit throttling on authentication endpoints.
# FedRAMP AC-7 (unsuccessful-logon attempts) + SC-5 (denial-of-service protection),
# SOC 2 CC6.1. Complements Devise :lockable (which locks a single account) by also
# limiting attempts per source IP and per targeted email across the login + reset flows.
#
# rack-attack's Railtie inserts the middleware automatically when the gem loads.
class Rack::Attack
  # Counter store: Redis in real environments (shared across thin workers; Redis is already
  # present for Sidekiq). A per-process MemoryStore in test keeps the suite hermetic and lets
  # the throttle spec clear counters without touching the shared Redis (where Sidekiq lives).
  Rack::Attack.cache.store =
    if Rails.env.test?
      ActiveSupport::Cache::MemoryStore.new
    else
      ActiveSupport::Cache::RedisCacheStore.new(url: ENV.fetch('REDIS_URL', 'redis://localhost:6379/0'))
    end

  ### Throttles ###

  # Login attempts by IP.
  throttle('logins/ip', limit: 10, period: 60.seconds) do |req|
    req.ip if req.path == '/users/sign_in' && req.post?
  end

  # Login attempts targeting a specific account (many IPs, one email).
  throttle('logins/email', limit: 10, period: 60.seconds) do |req|
    if req.path == '/users/sign_in' && req.post?
      req.params.dig('user', 'email').to_s.downcase.strip.presence
    end
  end

  # Password-reset requests by IP (also limits account-enumeration probing).
  throttle('password_resets/ip', limit: 5, period: 60.seconds) do |req|
    req.ip if req.path == '/users/password' && req.post?
  end

  # Throttled requests get Rack::Attack's default 429 (Too Many Requests) response.
end

# Keep throttling out of the way of the test suite by default; the throttle spec enables it
# explicitly for the cases it exercises.
Rack::Attack.enabled = false if Rails.env.test?
