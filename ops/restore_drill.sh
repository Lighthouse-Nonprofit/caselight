#!/bin/bash
# Restore drill: prove that a nightly dump PLUS the .env keys actually reconstitutes
# READABLE data. Required before any real client record lands on a box
# (docs/PRODUCTION-RESETTLEMENT.md go-live gate) and re-runnable afterwards.
#
# It restores into a SCRATCH database and never touches the live one, so it is safe
# to run on a production box. What it proves, in order:
#
#   1. encrypted columns are ciphertext AT REST (raw SQL cannot read a name)
#   2. a fresh dump restores cleanly into an empty database
#   3. the restored copy DECRYPTS with the keys from .env -- and with the exact
#      case preserved (the 2026-07 incident lowercased display names, so
#      "non-blank" is not a passing result; only a byte-identical read is)
#   4. deterministic search still finds the row by name (ignore_case scheme)
#   5. the Mongo history archive restores and is non-empty
#
# The canary is a synthetic client written with validate:false and deleted in the
# cleanup step; the drill's own dump files are removed so the backup directory keeps
# only real nightly output.
#
# Usage:  bash ops/restore_drill.sh            # tenant from TENANT_SHORT/.env, else slo4home
#         TENANT=other bash ops/restore_drill.sh
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/oscar}"
cd "$APP_DIR"

TENANT="${TENANT:-$(grep -E '^TENANT_SHORT=' .env 2>/dev/null | cut -d= -f2- || true)}"
TENANT="${TENANT:-slo4home}"
SCRATCH_PG="${SCRATCH_PG:-drill_restore}"
SCRATCH_MONGO="${SCRATCH_MONGO:-drill_history}"

db_user="$(grep -E '^DATABASE_USER=' .env | cut -d= -f2-)"
db_name="$(grep -E '^DATABASE_NAME=' .env | cut -d= -f2-)"
mongo_db="$(grep -E '^HISTORY_DATABASE_NAME=' .env | cut -d= -f2-)"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
canary="DRILL-CaNaRy-${stamp}"   # deliberately mixed case: step 3 is case-exact
fails=0

step() { printf '\n== %s\n' "$1"; }
ok()   { printf '   PASS  %s\n' "$1"; }
bad()  { printf '   FAIL  %s\n' "$1"; fails=$((fails + 1)); }

runner() { # runner <extra docker -e args...> -- <ruby>
  local envs=() ruby
  while [ "$1" != '--' ]; do envs+=("$1"); shift; done
  shift
  ruby="$1"
  docker compose exec -T "${envs[@]}" app bundle exec rails runner "$ruby" 2>/dev/null
}

psql_live() { docker compose exec -T db psql -U "$db_user" -d "$db_name" -tAc "$1"; }

cleanup() {
  step "cleanup"
  docker compose exec -T db psql -U "$db_user" -d postgres -c \
    "DROP DATABASE IF EXISTS ${SCRATCH_PG} WITH (FORCE)" >/dev/null 2>&1 || true
  docker compose exec -T mongo mongosh --quiet --eval \
    "db.getSiblingDB('${SCRATCH_MONGO}').dropDatabase()" >/dev/null 2>&1 || true
  if [ -n "${canary_id:-}" ]; then
    runner -e "TENANT=${TENANT}" -- "
      Apartment::Tenant.switch('${TENANT}') { Client.where(id: ${canary_id}).delete_all }
    " >/dev/null 2>&1 || true
  fi
  rm -f "${drill_pg:-}" "${drill_mongo:-}"
  echo "   scratch db + scratch history + canary + drill dumps removed"
}
trap cleanup EXIT

step "0. canary row in the live tenant (${TENANT})"
canary_id="$(runner -e "TENANT=${TENANT}" -- "
  Apartment::Tenant.switch('${TENANT}') do
    c = Client.new(given_name: '${canary}', family_name: 'Drill')
    c.save(validate: false)
    puts \"canary_id=#{c.id}\"
  end
" | grep -oP 'canary_id=\K\d+')"
[ -n "$canary_id" ] || { bad "could not write the canary"; exit 1; }
ok "client id=${canary_id} given_name=${canary}"

step "1. ciphertext at rest"
at_rest="$(psql_live "SELECT given_name FROM \"${TENANT}\".clients WHERE id = ${canary_id}")"
if [ -z "$at_rest" ]; then
  bad "raw column is empty -- nothing was stored"
elif printf '%s' "$at_rest" | grep -qiF "$canary"; then
  bad "raw column contains the plaintext name -- NOT encrypted"
else
  ok "raw column is opaque (${#at_rest} bytes of ciphertext)"
fi

step "2. fresh dump"
bash ops/nightly_dump.sh
drill_pg="$(ls -t "${APP_DIR}"/backups/pg-*.dump | head -1)"
drill_mongo="$(ls -t "${APP_DIR}"/backups/mongo-*.archive.gz | head -1)"
ok "pg=$(basename "$drill_pg") mongo=$(basename "$drill_mongo")"

step "3. restore into scratch database ${SCRATCH_PG}"
docker compose exec -T db psql -U "$db_user" -d postgres -c \
  "DROP DATABASE IF EXISTS ${SCRATCH_PG} WITH (FORCE)" >/dev/null
docker compose exec -T db psql -U "$db_user" -d postgres -c \
  "CREATE DATABASE ${SCRATCH_PG}" >/dev/null
# pg_restore chatters about pre-existing roles/extensions; only the row count matters.
docker compose exec -T db pg_restore -U "$db_user" -d "$SCRATCH_PG" \
  --no-owner --no-privileges < "$drill_pg" >/dev/null 2>&1 || true
restored="$(docker compose exec -T db psql -U "$db_user" -d "$SCRATCH_PG" -tAc \
  "SELECT count(*) FROM \"${TENANT}\".clients" | tr -d '[:space:]')"
if [ "${restored:-0}" -ge 1 ]; then ok "${TENANT}.clients restored (${restored} row(s))"
else bad "no client rows in the restored copy"; fi

step "4. the restored copy decrypts, case-exact"
read_back="$(runner -e "DATABASE_NAME=${SCRATCH_PG}" -e "TENANT=${TENANT}" -- "
  Apartment::Tenant.switch('${TENANT}') do
    c = Client.find_by(id: ${canary_id})
    puts \"name=#{c&.given_name}\"
    puts \"lookup=#{Client.where(given_name: '${canary}').count}\"
  end
")"
got="$(printf '%s' "$read_back" | grep -oP '^name=\K.*' || true)"
lookup="$(printf '%s' "$read_back" | grep -oP '^lookup=\K\d+' || true)"
if [ "$got" = "$canary" ]; then ok "decrypted byte-identical: ${got}"
elif [ -z "$got" ]; then bad "decrypted to nothing (wrong keys, or the row is missing)"
else bad "decrypted but CHANGED: expected '${canary}', got '${got}'"; fi
if [ "${lookup:-0}" = "1" ]; then ok "deterministic name lookup finds exactly 1"
else bad "deterministic name lookup returned ${lookup:-0}, expected 1"; fi

step "5. mongo history archive restores"
docker compose exec -T mongo mongorestore --archive --gzip --drop \
  --nsFrom="${mongo_db}.*" --nsTo="${SCRATCH_MONGO}.*" < "$drill_mongo" >/dev/null 2>&1 || true
collections="$(docker compose exec -T mongo mongosh --quiet --eval \
  "db.getSiblingDB('${SCRATCH_MONGO}').getCollectionNames().length" | tr -d '[:space:]')"
if [ "${collections:-0}" -ge 1 ]; then ok "history restored (${collections} collection(s))"
else bad "history archive restored no collections"; fi

step "result"
if [ "$fails" -eq 0 ]; then
  echo "   DRILL PASSED -- dump + .env keys reconstitute readable data on this box."
else
  echo "   DRILL FAILED -- ${fails} check(s) did not pass. Do NOT load real records."
fi
exit "$fails"
