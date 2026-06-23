require File.expand_path('../boot', __FILE__)

# Load only the frameworks CaseLight uses, instead of `require "rails/all"`. Omitting
# action_text, active_storage, action_cable, action_mailbox: they're unused, and on Rails 7.1
# their *.esm.js assets (ES modules) break the uglifier precompile ("Uglifier::Error" on
# actiontext.esm.js — uglifier can't parse import/export).
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

module CifWeb
  class Application < Rails::Application
    # Use the Rails 7.1 cache serialization format (the 6.1 default is deprecated, removed in 7.2).
    config.active_support.cache_format_version = 7.1

    config.middleware.use Apartment::Elevators::Subdomain
    config.middleware.insert_before Warden::Manager, Apartment::Elevators::Subdomain
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

    config.middleware.use Rack::Cors do
      allow do
        origins '*'
        resource '*',
          :headers => :any,
          :expose  => ['access-token', 'expiry', 'token-type', 'uid', 'client'],
          :methods => [:get, :post, :options, :delete, :put]
      end
    end

    # custom error page
    config.exceptions_app = self.routes
  end
end
