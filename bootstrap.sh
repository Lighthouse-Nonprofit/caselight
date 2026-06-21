#!/usr/bin/env bash
# bootstrap.sh - app-level deploy of OSCaR on the pilot box.
# Run as `ubuntu`, AFTER provision.sh and AFTER the docker group is active
# (reconnect the ssh session once if provision.sh just added the group).
#
# Idempotent where it can be: .env, the mongoid patch, the tenant, and the
# seed are all guarded so reruns do not duplicate work. The build/migrate/seed
# steps are the ones most likely to need a fix-and-rerun pass on the EOL stack.
#
# Requires Dockerfile and docker-compose.yml present in APP_DIR (scp them from
# the project first). Tune the four vars below or pass them as env.
set -euo pipefail

REPO_URL="${REPO_URL:-https://github.com/pannsamnang/oscar-web-os.git}"
APP_DIR="${APP_DIR:-$HOME/oscar}"
TENANT_SHORT="${TENANT_SHORT:-yourorg}"    # lowercase, no underscores; = subdomain label = Postgres schema
TENANT_FULL="${TENANT_FULL:-Your Organization}"

# 1. Code
if [ ! -d "$APP_DIR/.git" ]; then
  echo "==> cloning OSCaR"
  git clone "$REPO_URL" "$APP_DIR"
fi
cd "$APP_DIR"

# 2. Docker artifacts must be in place before we build
for f in Dockerfile docker-compose.yml; do
  [ -f "$f" ] || { echo "MISSING $f in $APP_DIR. scp it from the project, then rerun."; exit 1; }
done

# 3. .env (generated once, with fresh secrets; never commit this file)
if [ ! -f .env ]; then
  echo "==> generating .env with fresh secrets"
  cat > .env <<EOF
DATABASE_NAME=oscar_production
DATABASE_NAME_TEST=oscar_test
DATABASE_USER=oscar
DATABASE_PASSWORD=$(openssl rand -hex 24)
DATABASE_HOST=db
DATABASE_PORT=5432
HISTORY_DATABASE_NAME=oscar_history
HISTORY_DATABASE_HOST=mongo
REDIS_URL=redis://redis:6379/0
RAILS_ENV=production
SECRET_KEY_BASE=$(openssl rand -hex 64)
SENDER_EMAIL=nil
DEV_EMAIL=nil
ABLE_MANAGER_EMAIL=nil
GOOGLE_CLIENT_ID=nil
GOOGLE_CLIENT_SECRET=nil
# CarrierWave/fog (S3) creds. DUMMY placeholders so the production env loads and
# the app boots (the carrierwave initializer eager-loads fog in production and
# demands these). The pilot does NOT use real S3 — document upload to S3 will not
# work until real creds are set OR storage is switched to local disk. Open org
# decision; see NOTES.md finding #5.
AWS_ACCESS_KEY_ID=dummy
AWS_SECRET_ACCESS_KEY=dummy
FOG_DIRECTORY=dummy
FOG_REGION=us-east-1
EOF
  chmod 600 .env
fi

# 4. Make the Mongo host configurable (upstream hardcodes localhost:27017)
if grep -q "localhost:27017" config/mongoid.yml; then
  echo "==> patching config/mongoid.yml Mongo host -> env"
  # NOTE: delimiter is '#', not '|', because the replacement contains the Ruby
  # '||' operator; using '|' as the sed delimiter breaks parsing (see NOTES.md).
  sed -i "s#- localhost:27017#- <%= ENV['HISTORY_DATABASE_HOST'] || 'localhost' %>:27017#g" config/mongoid.yml
fi

# 4b. Build-time precompile guard (see NOTES.md finding #6).
#     assets:precompile loads the full production env, but there is NO database
#     reachable during the image build (host "db" only resolves on the compose
#     net at runtime). With eager_load=true AND the thredded initializer forcing
#     the User model to load (devise_token_auth runs table_exists? at class-load),
#     precompile aborts with PG::ConnectionBad. We neutralise BOTH triggers, but
#     ONLY when PRECOMPILE_ASSETS=true (set on the Dockerfile precompile RUN), so
#     runtime behaviour is unchanged. Idempotent.
if ! grep -q 'PRECOMPILE_ASSETS' config/environments/production.rb; then
  echo "==> guarding eager_load for precompile (production.rb)"
  sed -i 's#config\.eager_load = true#config.eager_load = ENV["PRECOMPILE_ASSETS"] != "true"#' config/environments/production.rb
fi
if ! grep -q 'PRECOMPILE_ASSETS' config/initializers/thredded.rb; then
  echo "==> guarding thredded user_class resolution for precompile (thredded.rb)"
  sed -i '/^Thredded\.current_user_method = /s#$# unless ENV["PRECOMPILE_ASSETS"] == "true"#' config/initializers/thredded.rb
fi
# Build-time precompile guard initializer. Two build-only problems, both gated on
# PRECOMPILE_ASSETS so runtime is untouched (sorts first as 00_). Always (re)written so
# edits here propagate on rerun (it is our generated file, safe to overwrite). #6/#7.
#  (1) The thredded ENGINE (gem code) resolves Thredded.user_class in a to_prepare
#      callback during initialize!, force-loading User regardless of the app-level
#      guards above; User's devise_token_auth concern probes the schema via
#      table_exists? at class-load -> PG::ConnectionBad with no DB. Degrade
#      table_exists? to false so any model can load without a database.
#  (2) The asset_sync gem hooks assets:precompile to UPLOAD assets to S3 (it
#      auto-configures from the dummy fog ENV vars) -> 403. ASSET_SYNC_ENABLED=false did
#      not stick, so disable it deterministically on AssetSync.config after_initialize
#      (runs after asset_sync configures, before the precompile rake hook reads it).
GUARD_INIT="config/initializers/00_precompile_no_db.rb"
echo "==> writing precompile build guard initializer ($GUARD_INIT)"
cat > "$GUARD_INIT" <<'RUBY'
# frozen_string_literal: true
# Build-time only (PRECOMPILE_ASSETS=true); no DB or S3 is reachable during the Docker
# image asset precompile. NO runtime effect (the flag is unset at runtime).
# See NOTES.md findings #6 and #7.
if ENV['PRECOMPILE_ASSETS'] == 'true'
  # (1) devise_token_auth probes the schema via table_exists? at class-load when User
  #     loads (thredded engine forces this). Degrade it to false with no DB reachable.
  module OscarPrecompileNoDb
    def table_exists?(*)
      super
    rescue StandardError
      false
    end
  end
  ActiveRecord::Base.singleton_class.prepend(OscarPrecompileNoDb)

  # (2) asset_sync hooks assets:precompile to upload to S3. Disable it on the config
  #     object directly (the ASSET_SYNC_ENABLED env var did not take). after_initialize
  #     runs after asset_sync's engine configures and before the precompile rake hook
  #     checks run_on_precompile.
  Rails.application.config.after_initialize do
    if defined?(AssetSync) && AssetSync.respond_to?(:config) && AssetSync.config
      AssetSync.config.run_on_precompile = false
      AssetSync.config.enabled = false
    end
  end
end
RUBY

# 4c. thin is in the :development group upstream, but our production image runs thin
#     (Dockerfile CMD). `bundle install --without development` excludes it, so the app
#     container dies with "command not found: thin" (exit 127). Move thin to the default
#     group so the prod bundle installs it. Gemfile.lock is group-agnostic, so no
#     bundle update is needed (changing the Gemfile does force a bundle reinstall layer).
#     Idempotent. See NOTES #8.
if grep -qE "^  gem 'thin'" Gemfile; then
  echo "==> moving thin gem out of :development to the default group (Gemfile)"
  sed -i "/^  gem 'thin'$/d" Gemfile
  printf "\n# thin moved to the default group so the production image installs it (NOTES #8)\ngem 'thin'\n" >> Gemfile
fi

# 4d. sidekiq.rb hardcodes redis://localhost; in Docker, redis is the 'redis' service.
#     Point both configure_server/_client at ENV['REDIS_URL'] (flagged in SETUP.md step 3),
#     keeping the localhost fallback. Idempotent. See NOTES #8.
if ! grep -q 'REDIS_URL' config/initializers/sidekiq.rb; then
  echo "==> pointing sidekiq.rb redis at ENV['REDIS_URL'] (was hardcoded localhost)"
  sed -i "s#'redis://localhost:6379/0'#ENV['REDIS_URL'] || 'redis://localhost:6379/0'#g" config/initializers/sidekiq.rb
fi

# 5. Build (slow; the EOL native gems live here)
echo "==> docker compose build"
docker compose build

# 6. Data services first, then wait for Postgres to accept connections
echo "==> starting db / mongo / redis"
docker compose up -d db mongo redis
echo "==> waiting for postgres"
until docker compose exec -T db pg_isready -U "$(grep ^DATABASE_USER .env | cut -d= -f2)" >/dev/null 2>&1; do
  sleep 2
done

# 7. Database: create then migrate the public/shared schema.
#    apartment clones this structure into each tenant schema at tenant create.
docker compose run --rm app bundle exec rake db:create 2>/dev/null || true
docker compose run --rm app bundle exec rake db:migrate

# 8. Tenant: create the apartment schema only if the org row is absent.
#    create_and_build_tanent() also runs Apartment::Tenant.create(short_name),
#    which builds the schema. Must come AFTER db:migrate.
echo "==> ensuring tenant '$TENANT_SHORT'"
if docker compose run --rm app bundle exec rails runner \
     "exit(Organization.where(short_name: '$TENANT_SHORT').exists? ? 0 : 1)"; then
  echo "    tenant already present, skipping"
else
  docker compose run --rm app bundle exec rails runner \
    "Organization.create_and_build_tanent(short_name: '$TENANT_SHORT', full_name: '$TENANT_FULL')"
fi

# 9. Seed base reference data once.
#    VERIFY: with apartment, confirm the seed lands where the app reads it. If
#    base data is missing inside the tenant, reseed within the tenant context,
#    e.g. rails runner "Apartment::Tenant.switch('$TENANT_SHORT'){ load 'db/seeds.rb' }"
if [ ! -f .seeded ]; then
  echo "==> seeding base data"
  docker compose run --rm app bundle exec rake db:seed && touch .seeded
fi

# 10. Up
echo "==> starting app + sidekiq"
docker compose up -d app sidekiq

echo "==> bootstrap complete."
echo "    Smoke test: browse https://<your-subdomain>/ , register the first user,"
echo "    create a Family + Client, attach a document, write a case note."
echo "    Future schema changes apply to all tenants via: rake apartment:migrate"
