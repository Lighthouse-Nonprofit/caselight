source 'https://rubygems.org'

gem 'rails', '6.0.6.1'
gem 'nokogiri', '~> 1.15.0'
gem 'loofah', '~> 2.3'
gem 'rails-html-sanitizer', '~> 1.4'
gem 'json', '~> 2.3.0'
gem 'tilt', '~> 2.0'
# ffi 1.17+ requires Ruby >= 3.0; cap it for Ruby 2.7.8 (transitive dep via listen/rb-inotify).
gem 'ffi', '< 1.17'
# concurrent-ruby 1.3.5 dropped the stdlib Logger require that Rails 6.0/6.1's
# ActiveSupport::LoggerThreadSafeLevel depends on -> uninitialized-constant NameError at boot.
# Cap below 1.3.5 (the require "logger" in application.rb covers the app; this covers rails CLI/rake too).
gem 'concurrent-ruby', '1.3.4'
gem 'erubis'
gem 'pg'
gem 'jquery-rails'
gem 'jquery-ui-rails'
# sass-rails 5.1.0 relaxed the railties cap to allow Rails 6 while still using ruby-sass
# (the sprockets engine), so the legacy bourbon/neat/bootstrap-sass scss keeps compiling —
# avoids migrating to sassc (sass-rails 6), which those old libraries don't support.
gem 'sass-rails', '~> 5.1.0'
gem 'sprockets', '~> 3.7'
gem 'uglifier',               '>= 1.3.0'
gem 'coffee-rails', '~> 4.2'
gem 'jbuilder',               '~> 2.0'
gem 'simple_form', '~> 4.0'
gem 'bootstrap-sass',         '~> 3.3.5'
gem 'devise', '~> 4.4'
gem 'haml-rails', '~> 1.0'
gem 'dotenv-rails', '~> 2.2'
gem 'roo',                    '~> 2.2'
gem 'fog'
gem 's3'
gem 'ffaker',                 '~> 2.1.0'
gem 'draper', '~> 3.0'
gem 'datagrid',               '~> 1.4.2'
gem 'active_model_serializers'
gem 'sinatra', '~> 2.0', require: false
gem 'rack-cors',              require: 'rack/cors'
gem 'rails-erd'
gem 'phony_rails',            '~> 0.12.11'
gem 'typhoeus'
gem 'foreman',                '~> 0.87'
gem 'cancancan', '~> 3.0'
gem 'pundit', '~> 2.0'
gem 'tinymce-rails',          '~> 4.5.6'
gem 'bootstrap-datepicker-rails', '~> 1.5'
gem 'select2-rails',          '~> 3.5.9.3'
gem 'jquery-validation-rails'
gem 'fullcalendar-rails',     '~> 3.2.0.0'
gem 'momentjs-rails',         '~> 2.17.1'
gem 'kaminari', '~> 1.1'
gem 'jquery-datatables-rails', '~> 3.4'
gem 'friendly_id',            '~> 5.1.0'
gem 'wicked_pdf',             '~> 1.0', '>= 1.0.6'
gem 'wkhtmltopdf-binary-edge', '~> 0.12.3.0'
gem 'browser',                '~> 2.1'
gem 'whenever',               '~> 0.9.4'
gem 'cocoon',                 '~> 1.2', '>= 1.2.9'
gem 'paper_trail', '~> 10.0'
gem 'carrierwave',            '~> 1.1.0'
gem 'mini_magick',            '~> 4.5'
gem 'chartkick',              '~> 2.0', '>= 2.0.2'
gem 'font-awesome-rails',     '~> 4.7'
gem 'spreadsheet',            '~> 1.1.3'
# 2.4.0 fixes the Rails 5.2 ActiveRecord::Migrator.schema_migrations_table_name removal;
# 2.10+ uses Array#any?(pattern) (Ruby 2.5+) which breaks on Ruby 2.3.3 — so cap below 2.10
# until the Ruby bump. Resolves to 2.9.0.
gem 'ros-apartment', '>= 2.4.0', '< 2.10.0', require: 'apartment'
gem 'dropzonejs-rails',       '~> 0.7.3'
# bourbon (~> 4.2) + neat (~> 1.8) removed: they were imported in application.scss but no
# mixins/functions were ever used, and bourbon 4.x pins thor ~> 0.19, which conflicts with
# Rails 6's railties (thor >= 0.20.3). Dropping the dead imports unblocks the thor bump.
gem 'jquery_query_builder-rails', '~> 0.2.2'
gem 'sidekiq',                '~> 4.1.0'
# Pin the mongo driver to 2.19.x: 2.20+ dropped MongoDB 3.6 (the pinned server) and require
# wire version >= 7/8 (server 4.0/4.2). 2.19.x still supports the 3.6 server (wire 6). The Mongo
# server bump (3.6 -> modern) is deferred to the Rails 7 / mongoid 8 rung, which forces it.
gem 'mongo', '~> 2.19.0'
gem 'mongoid', '~> 7.0'

group :development, :test do
  gem 'pry'
  gem 'rspec-rails', '~> 3.5'
  gem 'factory_bot_rails', '~> 4.8'
  gem 'launchy',              '~> 2.4', '>= 2.4.3'
  gem 'capybara',             '~> 2.5'
  gem 'poltergeist',          '~> 1.9.0'
  gem 'shoulda-whenever',     '~> 0.0.2'
  gem 'bullet', '~> 6.0'
  gem 'mongoid-rspec', '< 4.2'
end

group :staging, :demo, :production do
  gem 'appsignal', '~> 1.1.9'
  gem 'asset_sync'
end

group :staging do
  gem 'mail_interceptor', '~> 0.0.7'
end

group :development do
  gem 'letter_opener',        '~> 1.4.1'
  gem 'rubocop',              '~> 0.47.1', require: false
end

group :test do
  gem 'database_cleaner',     '~> 1.5', '>= 1.5.1'
  gem 'guard-rspec',          '~> 4.6'
  gem 'json_spec',            '~> 1.1', '>= 1.1.4'
  gem 'shoulda-matchers'
  gem 'rspec-sidekiq'
  gem 'rspec-activemodel-mocks'
end

# thin moved to the default group so the production image installs it (NOTES #8)
gem 'thin'
