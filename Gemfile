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
# POAM-017e (R9c): dartsass-rails (the maintained dart-sass compiler) replaced
# sass-rails 5.1 / ruby-sass 3.7.4 (EOL 2019). dart-sass compiles application.scss into
# app/assets/builds/application.css OUTSIDE sprockets (dartsass:build, auto-hooked into
# assets:precompile); sprockets just serves the built file. Prerequisites landed in R9a
# (glob imports expanded) and R9b (sprockets asset helpers eliminated). sass-rails' removal
# also lifts its `sprockets < 4.0` pin — the R10 Sprockets-4 blocker.
gem 'dartsass-rails', '~> 0.5'
# POAM-017e/R10: sprockets 4 (the maintained line; 3.x is frozen). Unblocked by R9c —
# sass-rails pinned `sprockets < 4.0`. Sprockets 4 reads app/assets/config/manifest.js
# for the precompile set and no longer ships the ruby-sass/coffee engines the R6/R9c
# neutralizing shims guarded against.
gem 'sprockets', '~> 4.2'
# sprockets-rails was only ever in the bundle as sass-rails' transitive dependency — with
# sass-rails gone it must be declared directly (config/application.rb requires
# 'sprockets/railtie', which this gem provides).
gem 'sprockets-rails'
# Terser (ES2015+-native JS minifier) replaced uglifier in Unit 11: uglifier wraps the
# ES5-only UglifyJS and cannot minify modern vendored JS (Chart.js v4's getters/arrows/const),
# even with harmony:true. Terser is the modern Rails default and handles ES5+ES6 alike.
gem 'terser',                 '~> 1.2'
# coffee-rails removed (POAM-017e): all 61 .coffee files were decaffeinated to ES2015+
# (mechanical conversion, semantics-preserving; sprockets requires are extensionless so
# the manifest needed no changes). execjs stays for terser.
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
# R11: haml 6 (the Hamlit-lineage rewrite; the last deliberate version pin). Exposure was
# audited before the bump: zero haml_tag/haml_concat/capture_haml/succeed/precede/object-ref
# usage, filters limited to :javascript/:css (both in haml 6 core), no Haml::Options config.
gem 'haml', '~> 6.3'
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
# sinatra REMOVED (Phase 6 / POAM-003): it existed only as the sidekiq-4 web-UI dependency, was
# require: false, and Sidekiq::Web was never mounted anywhere. sidekiq >= 6 ships its own rack app.
# rack-cors removed (Phase 1): the only CORS config was a vestigial `origins '*'` block for the
# removed mobile/token-auth API. Remaining /api endpoints are same-origin AJAX (no CORS needed).
gem 'rack-attack', '~> 6.7'   # Phase 2: brute-force / rate-limit throttling on auth endpoints (AC-7, SC-5)
# Explicit redis-rb for rack_attack's throttle store (config/initializers/rack_attack.rb uses raw
# Redis.new). Previously an implicit transitive dep of sidekiq 4; sidekiq 7 switched to redis-client,
# so without this line the redis gem would silently drop out of the bundle and break rack-attack.
gem 'redis', '~> 5.4'
gem 'lograge', '~> 0.14'      # Phase 3: structured (JSON) request logging with audit tags (AU-3)
gem 'rails-erd'
gem 'phony_rails',            '~> 0.15.0'
gem 'typhoeus'
gem 'foreman',                '~> 0.87'
gem 'cancancan', '~> 3.0'
gem 'pundit', '~> 2.0'
# tinymce-rails (~> 4.5) removed (POAM-017a): TinyMCE 4 hit EOL in 2022 — an unpatchable rich-text
# editor on the clinical-notes path. Replaced by Trix 2 (MIT, 37signals), vendored under
# vendor/assets (trix.js / trix.scss) like select2 below; the render path (render_rich_text
# sanitizer allowlist) is unchanged and already covers Trix's output tags.
gem 'bootstrap-datepicker-rails', '~> 1.5'
# select2-rails (~> 3.5.9.3) removed: it pins thor ~> 0.14, which conflicts with railties 6.1
# (thor ~> 1.0), and its only 6.1-compatible line is select2-rails 4.x = select2 v4 JS — a breaking
# API change the app's v3 usage (select2-selecting/removed events, .select2('val'), #select2-chosen)
# can't take. The v3 assets (select2.js / select2.scss / select2-bootstrap.css / images) are now
# vendored under vendor/assets, so `//= require select2` and `@import 'select2'` still resolve.
gem 'jquery-validation-rails'
# fullcalendar-rails (~> 3.9) + momentjs-rails removed (POAM-017d): the calendar runs on a
# vendored FullCalendar 6 standard bundle (vendor/assets/javascripts/fullcalendar.js) —
# jQuery/moment-free. moment's only call sites were inside calendars/index.js and died here.
gem 'google-apis-calendar_v3', require: false # Task -> Google Calendar sync (re-added; see REMOVED-FEATURES.md)
gem 'kaminari', '~> 1.1'
# jquery-datatables-rails removed (POAM-017e R9b): its DataTables asset was already shadowed
# by the vendored 1.13.11 (R5, jQuery-3 floor), and the gem's sass-rails dependency would pin
# `sprockets < 4.0` in the lock even after the compiler swap.
gem 'friendly_id',            '~> 5.7.0'
gem 'wicked_pdf',             '~> 2.8'  # was ~> 1.0 (PR #17); render API unchanged 1->2, keep wkhtmltopdf-binary-edge 0.12.6
gem 'wkhtmltopdf-binary-edge', '~> 0.12.6.0'
gem 'browser',                '~> 6.2'  # was ~> 2.1 (PR #25); firefox?/platform.mac? unchanged, vestigial modern? spec-stub removed
gem 'whenever',               '~> 1.1.2'
gem 'cocoon',                 '~> 1.2', '>= 1.2.9'
gem 'paper_trail', '~> 15.0'
gem 'carrierwave',            '~> 3.1'
gem 'mini_magick',            '~> 4.5'
# font-awesome-rails removed (POAM-017e R9b): the gem shipped only a .css.erb (sprockets
# font-path helpers dart-sass can't evaluate) + fonts. Now vendored as plain css
# (vendor/assets/stylesheets/font-awesome.css) + undigested fonts (public/fonts/font-awesome/).
gem 'spreadsheet',            '~> 1.3.5'
# ros-apartment 3.x supports Rails 7.0/7.1; on Ruby 3.3 the 3.1+ Ruby-version caps no longer bind.
gem 'ros-apartment', '~> 3.1', require: 'apartment'
gem 'dropzonejs-rails',       '~> 0.8.5'
# bourbon (~> 4.2) + neat (~> 1.8) removed: they were imported in application.scss but no
# mixins/functions were ever used, and bourbon 4.x pins thor ~> 0.19, which conflicts with
# Rails 6's railties (thor >= 0.20.3). Dropping the dead imports unblocks the thor bump.
gem 'jquery_query_builder-rails', '~> 0.5.0'
# sidekiq 4 -> 7 (Phase 6 / POAM-001: XSS + 2x DoS CVEs). 7.x uses redis-client internally (the
# explicit redis gem above keeps rack-attack working); Sidekiq.default_worker_options renamed to
# default_job_options (initializer updated); no Sidekiq::Extensions (.delay) usage existed to convert.
gem 'sidekiq',                '~> 7.3'
# connection_pool 3.0 changed TimedStack#pop's signature and crashes sidekiq 7.3's scheduler thread
# (ArgumentError at boot, caught by the U11 smoke). Pin to the 2.x line sidekiq 7 was built against.
gem 'connection_pool',        '~> 2.5'
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
  gem 'rubocop',              '~> 1.88.0', require: false
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
