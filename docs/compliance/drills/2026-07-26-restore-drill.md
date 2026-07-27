# Restore drill — 2026-07-26/27 (first execution; SSP §5 backups gate)

_Owner: Lighthouse Nonprofit Technologies. Executed on the pilot box during the block-3 hardening
session, immediately after the block-3 deploy (box `6468e98`). This record defines the drill's
PASS standard (none existed before tonight) and documents the first passing run._

## What was restored

The operator backup set `~/backups/block3-20260727/` (taken ~40 minutes before the drill, per the
OPERATIONS backup rule): `pg_dumpall.sql` (1,502,616 bytes — cluster globals + `oscar_production`
with its Apartment tenant schemas) and `mongodump.archive` (520,928 bytes — the shared history/audit
database).

**Method** (now the OPERATIONS.md restore runbook): throwaway `postgres:17` + `mongo:8.0`
containers joined to the compose network → `psql -U postgres -f` the dumpall (roles + databases
recreate; the app role's password hash rides in the dump) → `mongorestore --archive` → a one-off
app container with `DATABASE_HOST`/`HISTORY_DATABASE_HOST` pointed at the drill stores and the
box's own `.env` otherwise → evidence checks → teardown (`docker rm -f`, no volumes kept).

## PASS standard (defined by this drill, house style)

1. Restored tenant row counts match the live baseline exactly.
2. An encrypted value **decrypts to its exact live value** under the box's keys — Tier 4
   (deterministic, display-case-bearing) and Tier-1 reads under strict mode (a straggler would
   raise, so a clean read IS the integrity check).
3. The Mongo history/audit collections restore non-empty.

## Result: PASS

```
pg restore stderr lines: 0            (oscar_production recreated)
counts clients/families/cases = 27/10/26          (== live baseline)
tier4 exact-value decrypt: given_name="Yusuf"     (exact case — the 07-23 lesson)
tier1 strict-mode reads over 5 rows: ok=true
mongo access_logs/client_histories/task_histories = 1157/18/6
DRILL PASS ... teardown ... DRILL-COMPLETE
```

## Findings

1. **The recovery unit is dumps + `.env`, or an EBS snapshot — never dumps alone.** Every
   encrypted column's keys derive from `SECRET_KEY_BASE`, which `bootstrap.sh` generates per box
   and never commits. A dump set restored anywhere without that `.env` is **ciphertext-locked**.
   EBS snapshots include the `.env` (it lives on the volume); a dumps-only off-box strategy
   requires escrowing the `.env` alongside them. Recorded in OPERATIONS.md.
2. **Dump sets are plaintext files on an encrypted disk.** The SSP asks for "encrypted, tested
   backups": at-rest coverage today is the EBS volume encryption underneath `~/backups/`. For any
   dump set that leaves the box, encrypt it first (the `export:tenant` primitive:
   `openssl enc -aes-256-cbc -pbkdf2`). Guidance added to OPERATIONS.md.
3. The retention note stands (data-retention.md §3): a restore of expired data is healed by the
   deletion/purge paths re-running post-restore — the archive-gated purges make that safe.

## Still open on the backups gate

Automated daily EBS snapshots (infra; SECURITY.md baseline box) and the WORM tier for audit
archives remain inherited/infra hand-offs. The **"tested restore drill"** clause is now met and
repeatable: rerun `/tmp/restore_drill.sh`'s steps per the OPERATIONS runbook after any major
schema/encryption change, and at least quarterly.
