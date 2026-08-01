#!/usr/bin/env bash
# switch-flavor.sh <resettlement|youth> — on-demand flavor switch for DEMO boxes.
# Seeds the incoming flavor (taxonomy + synthetic demo), then removes the outgoing
# flavor entirely (rake flavor:unseed_* — aborts untouched if it smells real data),
# then reloads the app so labels flip. Flavors stay fully separate: one taxonomy
# visible at a time, each re-creatable from its seed rake.
#
# DEMO BOXES ONLY: refuses unless SEED_DEMO=true in .env (the demo-box marker).
# Production boxes never switch — one server = one flavor, forever.
set -euo pipefail
cd "$(dirname "$0")"

NEW="${1:?usage: ./switch-flavor.sh <resettlement|youth>}"
case "$NEW" in resettlement|youth) ;; *) echo "unknown flavor: $NEW" >&2; exit 1;; esac

grep -q '^SEED_DEMO=true' .env || {
  echo "refusing: SEED_DEMO=true not set in .env — this is not a demo box." >&2; exit 1; }

OLD=$(grep -E '^FLAVOR=' .env | cut -d= -f2- || true)
OLD="${OLD:-resettlement}"
if [ "$NEW" = "$OLD" ]; then echo "already on $NEW"; exit 0; fi
TENANT="${TENANT:-cases}"

echo "==> switching demo box flavor: $OLD -> $NEW (tenant=$TENANT)"

# 1. Flip the env first — flavor:seed and the unseed active-flavor guard both key
#    off it (docker compose run re-reads .env, so the container sees $NEW).
sed -i "s/^FLAVOR=.*/FLAVOR=$NEW/" .env

# 2. Seed the incoming flavor + its synthetic demo records (both idempotent).
docker compose run --rm -e TENANT="$TENANT" app bundle exec rake flavor:seed
docker compose run --rm -e TENANT="$TENANT" app bundle exec rake flavor:seed_demo
touch ".flavor_seeded.$NEW" ".flavor_demo_seeded.$NEW"

# 3. Remove the outgoing flavor: taxonomy + demo data. Hard-aborts (leaving data
#    in place) if any enrollment/filled form/list link survives the demo purge.
docker compose run --rm -e TENANT="$TENANT" -e CONFIRM_UNSEED=1 \
  app bundle exec rake "flavor:unseed_$OLD"
rm -f ".flavor_seeded.$OLD" ".flavor_demo_seeded.$OLD"

# 4. Reload so the locale overlay (labels) flips.
docker compose up -d --force-recreate app sidekiq

echo "==> done: demo box is now $NEW-flavored (was $OLD)."
