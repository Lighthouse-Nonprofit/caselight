require File.expand_path('../boot', __FILE__)

# Load only the frameworks CaseLight uses, instead of `require "rails/all"`. Omitting
# action_text, active_storage, action_cable, action_mailbox: they're unused (and historically
# their *.esm.js ES-module assets tripped the old uglifier precompile; the JS compressor is now
# Terser, which handles ES modules, but these frameworks stay omitted as genuinely unused).
require "rails"
require "active_record/railtie"
require "active_job/railtie"
require "action_controller/railtie"
require "action_view/railtie"
require "action_mailer/railtie"
require "sprockets/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

# Rails 5.1 removed support for referencing middleware by String, so application.rb now names the
# constants directly (below). The string form was resolved lazily — when the middleware stack was
# built, after the gems' autoloads were in place — whereas naming the constants forces them to exist
# at config-parse time. Bundler.require does not eager-load these two files, so require them here.
require 'apartment/elevators/subdomain'
require 'warden'

# Tenant routing that ALSO understands *.localhost dev hosts (e.g. cases.localhost). The base
# Subdomain elevator resolves the tenant via PublicSuffix, which does not recognise the `.localhost`
# TLD — so hosts like `cases.localhost` extract no subdomain and fall to the public schema (login then
# fails because the user lives in the tenant schema). `.localhost` is a browser *secure context*, which
# we want for testing WebAuthn passkeys locally without HTTPS, so accept it: treat the first label of a
# `.localhost` host as the tenant. Every other host (lvh.me, the prod nip.io host, IPs) is unchanged.
module Apartment
  module Elevators
    class SubdomainWithLocalhost < Subdomain
      # Share the parent's configured exclusions. config/initializers/apartment/subdomain_exclusions.rb
      # sets excluded_subdomains (e.g. 'www') on Subdomain, NOT on this subclass — and the inherited
      # parse_tenant_name reads self.class.excluded_subdomains. Without this delegation the subclass
      # would have an EMPTY exclusion list, so a 'www.example.com' request (the Rails test default host)
      # would try to switch to a nonexistent 'www' tenant and 500.
      def self.excluded_subdomains
        Apartment::Elevators::Subdomain.excluded_subdomains
      end

      def parse_tenant_name(request)
        host = request.host.to_s
        return super unless host.end_with?('.localhost')

        sub = host.split('.').first
        return nil if self.class.excluded_subdomains.include?(sub)
        sub.presence
      end
    end
  end
end

module CifWeb
  class Application < Rails::Application
    # Use the Rails 7.1 cache serialization format (the 6.1 default is deprecated, removed in 7.2).
    config.active_support.cache_format_version = 7.1

    config.middleware.use Apartment::Elevators::SubdomainWithLocalhost
    config.middleware.insert_before Warden::Manager, Apartment::Elevators::SubdomainWithLocalhost
    # Settings in config/environments/* take precedence over those specified here.
    # Application configuration should go into files in config/initializers
    # -- all .rb files in that directory are automatically loaded.

    # Set Time.zone default to the specified zone and make Active Record auto-convert to this zone.
    # Run "rake -D time" for a list of tasks for finding time zone names. Default is UTC.
    # config.time_zone = 'Bangkok'

    # The default locale is :en and all translations from config/locales/*.rb,yml are auto loaded.
    #config.i18n.load_path += Dir[Rails.root.join('my', 'locales', '*.{rb,yml}').to_s]
    config.i18n.default_locale = :en
    config.i18n.available_locales = [:en]
    config.i18n.load_path += Dir[Rails.root.join('config', 'locales', '**', '*.{rb,yml}')]

    # Rails 7 (zeitwerk) auto-registers every app/* dir as an autoload root, so app/classes is
    # managed automatically (advanced_searches/ -> AdvancedSearches namespace). The old explicit
    # paths are gone: lib has no .rb files, and the `app/classes/**` glob is invalid under zeitwerk
    # (it manages app/classes as a single namespaced root, not one root per nested dir).

    # Override rails template engine: erb to haml
    config.generators do |g|
      g.template_engine :haml
    end

    # CORS removed (FedRAMP AC-4 / SC-7). The wide-open `origins '*'` block existed only for the
    # mobile API + devise_token_auth, which were removed on the Rails 7.1 upgrade. The remaining
    # /api endpoints are same-origin AJAX helpers for the web UI — same-origin requests don't use
    # CORS, so no Access-Control headers are needed and none should be advertised.

    # Explicit security response headers — FedRAMP SC-7 / SI, SOC 2 CC6.6. Set here rather than
    # relying on Rails' implicit defaults (this app does not call config.load_defaults). Applied to
    # every response. HSTS is intentionally NOT set here — force_ssl emits it only over HTTPS.
    config.action_dispatch.default_headers = {
      'X-Frame-Options'                   => 'SAMEORIGIN',                    # clickjacking: same-origin framing only
      'X-Content-Type-Options'            => 'nosniff',                       # no MIME sniffing
      'X-XSS-Protection'                  => '0',                             # disable the legacy/buggy auditor (modern guidance)
      'X-Permitted-Cross-Domain-Policies' => 'none',                         # no Flash/PDF cross-domain policy
      'Referrer-Policy'                   => 'strict-origin-when-cross-origin'
    }

    # custom error page
    config.exceptions_app = self.routes
  end
end
