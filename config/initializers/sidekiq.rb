# sidekiq 7: default_worker_options was renamed (worker -> job vocabulary).
Sidekiq.default_job_options = { retry: 3, backtrace: true }

Sidekiq.configure_server do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end

Sidekiq.configure_client do |config|
  config.redis = { url: ENV['REDIS_URL'] || 'redis://localhost:6379/0' }
end