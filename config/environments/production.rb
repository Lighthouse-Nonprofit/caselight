Rails.application.configure do
  # Settings specified here will take precedence over those in config/application.rb.

  # Code is not reloaded between requests.
  config.cache_classes = true

  # Rails 6 host authorization (ActionDispatch::HostAuthorization) 403s requests whose Host
  # header isn't allow-listed. The pilot is multi-tenant by subdomain on one box behind a proxy.
  # Set APP_HOST in the box .env (e.g. "caselight.example.org") to allow it + its subdomains; if
  # unset, leave host auth unenforced so a bare-IP / proxied deploy still serves.
  if ENV['APP_HOST'].present?
    config.hosts << ENV['APP_HOST']
    config.hosts << ".#{ENV['APP_HOST']}"
    # Tenant links use Rails' :subdomain url option, which builds "<subdomain>.<request.domain>".
    # request.domain returns the last (tld_length + 1) host labels, so derive tld_length from the
    # base (APP_HOST minus its leading tenant label) — otherwise a multi-label host like
    # cases.18-225-4-220.nip.io yields request.domain "nip.io" and links break to cases.nip.io.
    # base "18-225-4-220.nip.io" has 2 dots -> tld_length 2 -> domain "18-225-4-220.nip.io",
    # subdomain "cases". (A normal "cases.example.org" -> base "example.org" -> 1 -> example.org.)
    config.action_dispatch.tld_length = [ENV['APP_HOST'].split('.', 2).last.count('.'), 1].max
  else
    config.hosts.clear
  end

  # Eager load code on boot. This eager loads most of Rails and
  # your application in memory, allowing both threaded web servers
  # and those relying on copy on write to perform better.
  # Rake tasks automatically ignore this option for performance.
  config.eager_load = ENV["PRECOMPILE_ASSETS"] != "true"

  # Full error reports are disabled and caching is turned on.
  config.consider_all_requests_local       = false
  config.action_controller.perform_caching = true

  # Enable Rack::Cache to put a simple HTTP cache in front of your application
  # Add `rack-cache` to your Gemfile before enabling this.
  # For large-scale production use, consider using a caching reverse proxy like
  # NGINX, varnish or squid.
  # config.action_dispatch.rack_cache = true

  # Disable serving static files from the `/public` folder by default since
  # Apache or NGINX already handles this.
  config.serve_static_files = ENV['RAILS_SERVE_STATIC_FILES'].present?

  # Compress JavaScripts and CSS. harmony: true lets uglifier minify ES6 (some bundled/vendored
  # JS now uses `const`/arrow fns); without it precompile aborts on "Unexpected token: keyword (const)".
  config.assets.js_compressor = Uglifier.new(harmony: true)
  # config.assets.css_compressor = :sass


  config.action_controller.asset_host = "//#{ENV['S3_BUCKET_NAME']}.s3.amazonaws.com" if ENV['S3_BUCKET_NAME'].present?
  config.assets.prefix = "/assets"
  # Do not fallback to assets pipeline if a precompiled asset is missed.
  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  # Asset digests allow you to set far-future HTTP expiration dates on all assets,
  # yet still be able to expire them through the digest params.
  # Mailer link/asset host: use APP_HOST (the deploy's public host), not the stale upstream
  # oscarhq.com; fall back to localhost when unset. (Web tenant links are built by
  # SubdomainHelper#with_subdomain, which derives the shared base domain from APP_HOST directly.)
  config.action_mailer.asset_host = ENV['APP_HOST'].present? ? "https://#{ENV['APP_HOST']}" : nil
  config.action_mailer.default_url_options = { host: ENV['APP_HOST'].presence || 'localhost' }
  config.assets.digest = true
  config.assets.enabled = true
  config.assets.initialize_on_precompile = true

  config.action_mailer.perform_deliveries = true
  config.action_mailer.raise_delivery_errors = true
  config.action_mailer.delivery_method = :smtp

  config.action_mailer.smtp_settings = {
    address:               'email-smtp.us-east-1.amazonaws.com',
    authentication:        :login,
    user_name:             ENV['AWS_SES_USER_NAME'],
    password:              ENV['AWS_SES_PASSWORD'],
    enable_starttls_auto:  true,
    port:                  465,
    openssl_verify_mode:   OpenSSL::SSL::VERIFY_NONE,
    ssl:                   true,
    tls:                   true
  }
  # `config.assets.precompile` and `config.assets.version` have moved to config/initializers/assets.rb

  # Specifies the header that your server uses for sending files.
  # config.action_dispatch.x_sendfile_header = 'X-Sendfile' # for Apache
  # config.action_dispatch.x_sendfile_header = 'X-Accel-Redirect' # for NGINX

  # Force all access to the app over SSL, use Strict-Transport-Security, and use secure cookies.
  # config.force_ssl = true

  # Use the lowest log level to ensure availability of diagnostic information
  # when problems arise.
  config.log_level = :debug

  # Prepend all log lines with the following tags.
  # config.log_tags = [ :subdomain, :uuid ]

  # Use a different logger for distributed setups.
  # config.logger = ActiveSupport::TaggedLogging.new(SyslogLogger.new)

  # Use a different cache store in production.
  # config.cache_store = :mem_cache_store

  # Enable serving of images, stylesheets, and JavaScripts from an asset server.
  # config.action_controller.asset_host = 'http://assets.example.com'

  # Ignore bad email addresses and do not raise email delivery errors.
  # Set this to true and configure the email server for immediate delivery to raise delivery errors.
  # config.action_mailer.raise_delivery_errors = false

  # Enable locale fallbacks for I18n (makes lookups for any locale fall back to
  # the I18n.default_locale when a translation cannot be found).
  config.i18n.fallbacks = true

  # Send deprecation notices to registered listeners.
  config.active_support.deprecation = :notify

  # Use default logging formatter so that PID and timestamp are not suppressed.
  config.log_formatter = ::Logger::Formatter.new

  # Do not dump schema after migrations.
  config.active_record.dump_schema_after_migration = false
end
