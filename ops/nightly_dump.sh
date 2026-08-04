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

# Postgres: every schema (public + one per tenant) in one custom-format dump.
docker compose exec -T db pg_dump -U "$db_user" -d "$db_name" -Fc \
  > "$dest/pg-${db_name}-${stamp}.dump"

# Mongo: the change/audit history store.
docker compose exec -T mongo mongodump --db "$mongo_db" --archive --gzip \
  > "$dest/mongo-${mongo_db}-${stamp}.archive.gz"

chmod 600 "$dest"/pg-*.dump "$dest"/mongo-*.archive.gz 2>/dev/null || true

# Rotate: keep KEEP_DAYS locally; AWS Backup holds the longer horizon (35 days).
find "$dest" -maxdepth 1 -type f \( -name 'pg-*.dump' -o -name 'mongo-*.archive.gz' \) \
  -mtime "+${KEEP_DAYS}" -delete

pg_size="$(stat -c %s "$dest/pg-${db_name}-${stamp}.dump")"
mongo_size="$(stat -c %s "$dest/mongo-${mongo_db}-${stamp}.archive.gz")"
echo "[nightly_dump] ${stamp} pg=${pg_size}B mongo=${mongo_size}B kept=${KEEP_DAYS}d"

# Fail loudly on a suspiciously small dump — a silent 0-byte backup is worse than none.
if [ "$pg_size" -lt 10000 ]; then
  echo "[nightly_dump] FAIL: postgres dump is implausibly small (${pg_size}B)" >&2
  exit 1
fi
