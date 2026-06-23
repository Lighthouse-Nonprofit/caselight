require File.expand_path('../boot', __FILE__)

# Rails 6.0/6.1 reference ActiveSupport::LoggerThreadSafeLevel::Logger, but concurrent-ruby
# 1.3.5+ no longer transitively requires Ruby's stdlib Logger, so it is an uninitialized
# constant at boot. Require it explicitly before Rails loads. (Fixed upstream in Rails 7.1.)
require "logger"

require "rails/all"

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
