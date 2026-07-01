source 'https://rubygems.org'

gem 'rails', '~> 7.2.3', '>= 7.2.3.1'  # 7.2 closes POAM-005b Rails CVEs + enables devise-two-factor 6.4 (MFA)
gem 'nokogiri', '~> 1.16'
gem 'loofah', '~> 2.3'
gem 'rails-html-sanitizer', '~> 1.4'
gem 'json', '>= 2.3'
gem 'tilt', '~> 2.0'
# ffi + concurrent-ruby unpinned on Ruby 3.3 (the < 1.17 / 1.3.4 caps were for Ruby 2.7). The
# require "logger" in application.rb still guards the concurrent-ruby/Logger boot NameError (Rails 7.0).
gem 'erubis'
# Rails 7's postgresql adapter requires pg >= 1.1; pg 1.5/1.6 run on Ruby 3.3 and still support
# the pinned PostgreSQL 9.6 server (libpq 9.3+).
gem 'pg', '~> 1.5'
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
gem 'simple_form', '~> 5.4'  # 5.4.1 closes POAM-002 (CVE-2019-16676 / GHSA-r74q-gxcg-73hx)
gem 'bootstrap-sass',         '~> 3.4.1'
gem 'devise', '~> 5.0', '>= 5.0.4'  # 5.0.4 closes POAM-009 (CVE-2026-32700, CVE-2026-40295)
gem 'devise-security', '~> 0.18'    # Phase 2: password complexity + history/no-reuse (IA-5)
gem 'devise-two-factor', '~> 6.4'   # Phase 2: TOTP MFA (IA-2(1)); otp_secret via AR Encryption
gem 'rqrcode', '~> 2.0'             # QR codes for TOTP enrollment
# Phase 2: WebAuthn passkeys (IA-2 — phishing-resistant authenticator). Used DIRECTLY via
# WebAuthn::RelyingParty (registration/authentication ceremonies + FakeClient for specs) rather
# than via devise-passkeys' :passkey_authenticatable module — the app's custom two-step
# SessionsController (#create/#verify_otp) owns the login flow, and hand-wiring new ceremony
# endpoints keeps passkeys strictly ADDITIVE without re-touching the password/OTP devise strategy.
gem 'webauthn', '~> 3.4'
# haml-rails 2.x gives Rails 6 compatibility; pin haml itself to 5.2 — haml 6 is a parser
# rewrite that risks breaking the app's many .haml views. (haml 6 migration is its own future step.)
gem 'haml', '~> 5.2'
gem 'haml-rails', '~> 2.0'
gem 'dotenv-rails', '~> 2.2'
gem 'roo',                    '~> 2.2'
# Ruby 3.4+/4.0 dropped csv from the default gems; roo (and CSV report exports)
# require it, so it must be an explicit dependency now (Ruby 4 migration).
gem 'csv'
# fog-aws only (was the `fog` meta-gem): fog pulls every provider, and fog-rackspace 0.1.6
# fails to load on Ruby 3.3. carrierwave's optional S3 path uses provider 'AWS' = fog-aws.
gem 'fog-aws'
gem 'ffaker',                 '~> 2.25.0'
gem 'draper', '~> 4.0'
gem 'datagrid',               '~> 1.4.2'
gem 'active_model_serializers', '~> 0.10.0'
gem 'sinatra', '~> 2.0', require: false
# rack-cors removed (Phase 1): the only CORS config was a vestigial `origins '*'` block for the
# removed mobile/token-auth API. Remaining /api endpoints are same-origin AJAX (no CORS needed).
gem 'rack-attack', '~> 6.7'   # Phase 2: brute-force / rate-limit throttling on auth endpoints (AC-7, SC-5)
gem 'lograge', '~> 0.14'      # Phase 3: structured (JSON) request logging with audit tags (AU-3)
gem 'rails-erd'
gem 'phony_rails',            '~> 0.15.0'
gem 'typhoeus'
gem 'foreman',                '~> 0.87'
gem 'cancancan', '~> 3.0'
gem 'pundit', '~> 2.0'
# ~> 4.5 (not 4.5.6): stays on the TinyMCE 4 editor (the app's init JS is v4) but allows a later
# 4.x gem that uses File.exist? — 4.5.7 calls File.exists?, removed in Ruby 3.2.
gem 'tinymce-rails',          '~> 4.5'
gem 'bootstrap-datepicker-rails', '~> 1.5'
# select2-rails (~> 3.5.9.3) removed: it pins thor ~> 0.14, which conflicts with railties 6.1
# (thor ~> 1.0), and its only 6.1-compatible line is select2-rails 4.x = select2 v4 JS — a breaking
# API change the app's v3 usage (select2-selecting/removed events, .select2('val'), #select2-chosen)
# can't take. The v3 assets (select2.js / select2.scss / select2-bootstrap.css / images) are now
# vendored under vendor/assets, so `//= require select2` and `@import 'select2'` still resolve.
gem 'jquery-validation-rails'
gem 'fullcalendar-rails',     '~> 3.9.0.0'
gem 'momentjs-rails',         '~> 2.29.4'
gem 'google-apis-calendar_v3', require: false # Task -> Google Calendar sync (re-added; see REMOVED-FEATURES.md)
gem 'kaminari', '~> 1.1'
gem 'jquery-datatables-rails', '~> 3.4'
gem 'friendly_id',            '~> 5.7.0'
gem 'wicked_pdf',             '~> 2.8'  # was ~> 1.0 (PR #17); render API unchanged 1->2, keep wkhtmltopdf-binary-edge 0.12.6
gem 'wkhtmltopdf-binary-edge', '~> 0.12.6.0'
gem 'browser',                '~> 6.2'  # was ~> 2.1 (PR #25); firefox?/platform.mac? unchanged, vestigial modern? spec-stub removed
gem 'whenever',               '~> 1.1.2'
gem 'cocoon',                 '~> 1.2', '>= 1.2.9'
gem 'paper_trail', '~> 15.0'
gem 'carrierwave',            '~> 3.1'
gem 'mini_magick',            '~> 4.5'
gem 'font-awesome-rails',     '~> 4.7'
gem 'spreadsheet',            '~> 1.3.5'
# ros-apartment 3.x supports Rails 7.0/7.1; on Ruby 3.3 the 3.1+ Ruby-version caps no longer bind.
gem 'ros-apartment', '~> 3.1', require: 'apartment'
gem 'dropzonejs-rails',       '~> 0.8.5'
# bourbon (~> 4.2) + neat (~> 1.8) removed: they were imported in application.scss but no
# mixins/functions were ever used, and bourbon 4.x pins thor ~> 0.19, which conflicts with
# Rails 6's railties (thor >= 0.20.3). Dropping the dead imports unblocks the thor bump.
gem 'jquery_query_builder-rails', '~> 0.5.0'
gem 'sidekiq',                '~> 4.1.0'
# mongo driver unpinned now that the server is MongoDB 6.0 (the 2.19 cap was only to keep the
# EOL 3.6 server working). mongoid ~> 8.0 pulls a compatible mongo 2.x.
gem 'mongoid', '~> 8.0'

group :development, :test do
  gem 'pry'
  # Test stack bumped for Rails 7.0 / Ruby 3.3 (the old caps don't support either):
  gem 'rspec-rails', '~> 8.0'        # was ~> 3.5 -> 6.0 -> 8.0 (PR #20); needs config.fixture_paths (done)
  gem 'factory_bot_rails', '~> 6.0'  # was ~> 4.8
  gem 'launchy',              '~> 2.4', '>= 2.4.3'
  gem 'capybara',             '~> 3.0' # was ~> 2.5
  # poltergeist (~> 1.9.0) removed: PhantomJS is dead and the gem doesn't run on Ruby 3.3. The
  # feature specs that used it were already deferred to a cuprite port (see REMOVED-FEATURES.md).
  gem 'shoulda-whenever',     '~> 0.0.2'
  gem 'bullet', '~> 7.0'             # was ~> 6.0 (6.x rejects ActiveRecord 7.0)
  gem 'mongoid-rspec', '~> 4.2'      # was < 4.2
  # Security scanning (Phase 0 hardening; run in CI + locally, not required at boot):
  gem 'brakeman',      require: false  # SAST — Rails static security analysis
  gem 'bundler-audit', require: false  # dependency CVE scanning vs the ruby-advisory-db
end

group :staging, :demo, :production do
  gem 'asset_sync'
end

group :staging do
  gem 'mail_interceptor', '~> 0.0.7'
end

group :development do
  gem 'letter_opener',        '~> 1.10.0'
  gem 'rubocop',              '~> 1.88.1', require: false
end

group :test do
  # database_cleaner 2.0 split into adapter gems; the AR adapter supports Rails 7.1 (1.99 called
  # the removed ActiveRecord::SchemaMigration.table_name). Provides the DatabaseCleaner constant.
  gem 'database_cleaner-active_record', '~> 2.0'
  gem 'guard-rspec',          '~> 4.6'
  gem 'json_spec',            '~> 1.1', '>= 1.1.4'
  gem 'shoulda-matchers'
  gem 'rspec-sidekiq'
  gem 'rspec-activemodel-mocks'
end

# thin moved to the default group so the production image installs it (NOTES #8)
gem 'thin'
