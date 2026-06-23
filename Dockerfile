# Dockerfile - CaseLight (Ruby 3.3 / Rails 7.x), modernized off the EOL 2.3.3/4.2.2 stack.
# The build, not the run, is where you will spend time. See OPERATIONS.md.

FROM ruby:3.3

# ruby:3.3 is Debian Bookworm (current stable), apt mirrors live — normal install.
# Only libpq-dev (for the pg gem) is required; gcc/make/git ship in the base image.
RUN apt-get update \
 && apt-get install -y --no-install-recommends libpq-dev \
 && rm -rf /var/lib/apt/lists/*

# Node is needed only for execjs asset precompilation. Binary tarball keeps the
# version pinned and independent of apt.
RUN curl -fsSL https://nodejs.org/dist/v8.17.0/node-v8.17.0-linux-x64.tar.xz \
      | tar -xJ -C /usr/local --strip-components=1

WORKDIR /app

# Use the bundler that ships with ruby:3.3 (2.5.x) — it reads the lockfile and is current
# for Ruby 3.3 (the old 2.1.4 pin was for the Ruby 2.3 era).

COPY Gemfile Gemfile.lock ./
# Build-time bundle groups to skip. Default (prod) skips development+test -> a lean
# runtime image. The dev/test image overrides this via the docker-compose.dev.yml build
# arg ("staging demo production") so rspec/capybara/factories are baked in and survive
# rebuilds, giving a repeatable per-rung test loop for the Rails upgrade.
ARG BUNDLE_WITHOUT="development test"
RUN bundle install --jobs 4 --retry 3 --without ${BUNDLE_WITHOUT}

COPY . .

# Precompile assets in the image so the small instance never runs the
# memory-hungry pipeline at deploy time. The dummy secret is build-only.
#
# assets:precompile loads the full production environment, which runs
# config/initializers/carrierwave.rb. In production that initializer eager-loads
# fog and REQUIRES aws_access_key_id/aws_secret_access_key, so a bare precompile
# aborts with ArgumentError. Supply build-only dummy creds (same idea as the
# dummy SECRET_KEY_BASE). Fog only checks the keys are present at init; it makes
# no network call, so no real S3 is contacted. Runtime gets matching dummies
# from .env. Real S3-vs-local-disk storage is an open org decision (see NOTES).
# PRECOMPILE_ASSETS=true: there is no DB reachable during the build, but the prod
# env load force-loads the User model (eager_load + the thredded initializer), and
# devise_token_auth runs a table_exists? DB query at class-load -> PG::ConnectionBad.
# bootstrap.sh guards both triggers behind this flag so precompile skips the DB while
# runtime stays unchanged. See NOTES.md finding #6.
# ASSET_SYNC_ENABLED=false: the asset_sync gem hooks assets:precompile and tries to
# UPLOAD the compiled assets to an S3 bucket (it auto-configures from the dummy
# FOG_DIRECTORY/AWS vars above), which 403s with dummy creds. We don't use S3 for the
# pilot, and asset_sync only runs at precompile, so disabling it here is correct and
# has no runtime effect. AssetSync.sync early-returns `unless enabled?`. See NOTES #7.
RUN SECRET_KEY_BASE=dummy RAILS_ENV=production PRECOMPILE_ASSETS=true \
    ASSET_SYNC_ENABLED=false \
    AWS_ACCESS_KEY_ID=dummy AWS_SECRET_ACCESS_KEY=dummy \
    FOG_DIRECTORY=dummy FOG_REGION=us-east-1 \
    bundle exec rake assets:precompile

EXPOSE 3000
CMD ["bundle", "exec", "thin", "start", "-a", "0.0.0.0", "-p", "3000", "-e", "production"]
