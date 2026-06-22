# Makefile - local dev shortcuts for CaseLight. Requires Docker Desktop (WSL2 backend).
# These wrap the explicit -f flags so the production box never loads the dev overlay.

COMPOSE = docker compose -f docker-compose.yml -f docker-compose.dev.yml

.PHONY: dev dev-build dev-setup dev-down dev-console dev-logs

dev-build:    ## Build the image (run this after a Gemfile change)
	$(COMPOSE) build

dev:          ## Start the full stack in dev mode (browse http://cases.localhost:3000)
	$(COMPOSE) up

dev-setup:    ## One-time: create + migrate the dev DB, tenant, and seed
	$(COMPOSE) up -d db mongo redis
	@echo ">> waiting for postgres to accept connections..."
	@until $(COMPOSE) exec -T db pg_isready -U oscar >/dev/null 2>&1; do echo "   ...waiting for postgres"; sleep 2; done
	$(COMPOSE) run --rm app bundle exec rake db:create db:migrate
	$(COMPOSE) run --rm app bundle exec rails runner "Organization.create_and_build_tanent(short_name: 'cases', full_name: 'Dev')"
	$(COMPOSE) run --rm app bundle exec rake db:seed
	@echo ">> Now create a dev admin: 'make dev-console', then run the User.create! from DEVELOPMENT.md inside the cases tenant."

dev-down:     ## Stop the stack
	$(COMPOSE) down

dev-console:  ## Rails console in the dev container
	$(COMPOSE) run --rm app bundle exec rails console

dev-logs:     ## Tail the app logs
	$(COMPOSE) logs -f app
