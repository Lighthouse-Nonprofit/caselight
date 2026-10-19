#!/bin/bash
# Nightly logical backup: Postgres (all tenant schemas) + Mongo history, written to
# ~/oscar/backups and rotated locally. Installed as a cron by config/schedule.rb.
#
# WHY BOTH THIS AND EBS SNAPSHOTS: the AWS Backup snapshot restores a whole box
# (including .env, hence the encryption keys) but is coarse — you cannot pull one
# table out of it. These dumps give granular recovery. Neither is sufficient alone:
#
#   RECOVERY UNIT = a dump PLUS .env  (or a whole-volume snapshot)
#
# The 2026-07 restore drill proved dumps by themselves are ciphertext-locked: every
# encrypted column needs AR_ENCRYPTION_* / SECRET_KEY_BASE from .env to read.
# .env is deliberately NOT copied here — it belongs in the snapshot and in the
# owner's password manager, not in a file next to the data it unlocks.
set -euo pipefail

APP_DIR="${APP_DIR:-$HOME/oscar}"
KEEP_DAYS="${KEEP_DAYS:-14}"
cd "$APP_DIR"

stamp="$(date -u +%Y%m%dT%H%M%SZ)"
dest="$APP_DIR/backups"
mkdir -p "$dest"
chmod 700 "$dest"

db_user="$(grep -E '^DATABASE_USER=' .env | cut -d= -f2-)"
db_name="$(grep -E '^DATABASE_NAME=' .env | cut -d= -f2-)"
mongo_db="$(grep -E '^HISTORY_DATABASE_NAME=' .env | cut -d= -f2-)"

# Postgres: every schema (public + one per tenant) in one custom-format dump. Written as .partial
# and renamed only after pg_restore can list it — a half-written file must never count as a backup
# (set -e alone left the partial file behind, and the freshness checks would have trusted it).
pg_out="$dest/pg-${db_name}-${stamp}.dump"
docker compose exec -T db pg_dump -U "$db_user" -d "$db_name" -Fc > "$pg_out.partial"
tables="$(docker compose exec -T db pg_restore --list < "$pg_out.partial" 2>/dev/null | grep -c 'TABLE DATA' || true)"
if [ "${tables:-0}" -lt 20 ]; then
  echo "[nightly_dump] FAIL: pg_restore --list sees only ${tables:-0} TABLE DATA entries in the new dump" >&2
  rm -f "$pg_out.partial"; exit 1
fi
mv "$pg_out.partial" "$pg_out"

# Mongo: the change/audit history store (same partial-then-rename discipline).
mongo_out="$dest/mongo-${mongo_db}-${stamp}.archive.gz"
docker compose exec -T mongo mongodump --db "$mongo_db" --archive --gzip > "$mongo_out.partial"
if ! gzip -t "$mongo_out.partial" 2>/dev/null || [ "$(stat -c %s "$mongo_out.partial")" -lt 1000 ]; then
  echo "[nightly_dump] FAIL: mongo archive is not a valid gzip or is implausibly small" >&2
  rm -f "$mongo_out.partial"; exit 1
fi
mv "$mongo_out.partial" "$mongo_out"

chmod 600 "$dest"/pg-*.dump "$dest"/mongo-*.archive.gz 2>/dev/null || true

# Rotate: keep KEEP_DAYS locally; AWS Backup holds the longer horizon (35 days).
find "$dest" -maxdepth 1 -type f \( -name 'pg-*.dump' -o -name 'mongo-*.archive.gz' \) \
  -mtime "+${KEEP_DAYS}" -delete

pg_size="$(stat -c %s "$dest/pg-${db_name}-${stamp}.dump")"
mongo_size="$(stat -c %s "$dest/mongo-${mongo_db}-${stamp}.archive.gz")"
echo "[nightly_dump] ${stamp} pg=${pg_size}B (${tables} tables) mongo=${mongo_size}B kept=${KEEP_DAYS}d"

# Fail loudly on a suspiciously small dump — a silent 0-byte backup is worse than none.
if [ "$pg_size" -lt 10000 ]; then
  echo "[nightly_dump] FAIL: postgres dump is implausibly small (${pg_size}B)" >&2
  exit 1
fi
