# OPERATIONS — running the CaseLight pilot box

The operator runbook for the single-box pilot deployment. Referenced by `Dockerfile`,
`docker-compose.yml`, `bootstrap.sh`, the SSP (SC-8 evidence), and the incident-response
policy. Data-handling posture and the real-data production gate live in
[`SECURITY.md`](SECURITY.md); this file is *how to operate*, not *what is allowed*.

## The box

One AWS EC2 instance, reached over **SSH-over-SSM** (no public SSH port). The repo lives at
`~/oscar` on the box; the stack is Docker Compose (app, sidekiq, postgres 17, mongo 8, redis 7,
and Caddy behind the `proxy` profile). Provisioning (Docker + compose plugin, docker group for
the deploy user) is a one-time manual step; everything after that is `bootstrap.sh`.

## Deploying

```sh
cd ~/oscar && nohup bash bootstrap.sh > ~/deploy-$(date +%Y%m%d).log 2>&1 < /dev/null &
```

`bootstrap.sh` is **one-shot and idempotent**: it hard-syncs to `origin/main`, rebuilds the
image (production bakes source + precompiled assets — a view/SCSS change is invisible without
the rebuild), runs `db:migrate` + `apartment:migrate`, runs the encryption stages (below), and
brings the stack up. Rerun it any time; run it detached (SSM sessions drop).

Two behaviors worth knowing, both born from the 2026-07-22 incident:

- **Self-update guard** — if the sync changes `bootstrap.sh` itself, the script re-execs the
  fresh copy exactly once (`BOOTSTRAP_REEXEC=1`). Without this, bash keeps executing the *old*
  script text, so new deploy stages silently don't run in the deploy that introduces them.
- **Encryption-stage invariants** — the tier backfill (`encryption:backfill`) and the name
  reencrypt (`encryption:reencrypt_client_names`) run on **every** deploy, so both are written
  to be safe on re-run: they read columns via `read_attribute` (never a model reader, which can
  be overridden), they refuse to overwrite a non-NULL stored value with a nil read, and the
  reencrypt skips any row whose `original_*` sidecar is already populated (a clean re-run
  reports `re-encrypted=0`). If a deploy log shows `SKIPPING column` warnings, stop and
  investigate before re-running anything — that is the guard refusing to destroy data.
  Full narrative: `docs/compliance/incidents/2026-07-22-tier4-backfill-data-loss.md`.
- **Strict mode (since 2026-07-26)** — the app runs `support_unencrypted_data=false`: a
  non-envelope value in an encrypted column raises on read instead of being tolerated. The two
  migration rakes above re-enable the window for their own process, so the deploy stages still
  heal stragglers exactly as before; if the APP ever throws
  `ActiveRecord::Encryption::Errors::Decryption`, a straggler slipped in outside the deploy path —
  run `encryption:backfill` for its tier, then `encryption:verify`.

## Verifying a deploy (by state, not logs)

```sh
cd ~/oscar && git rev-parse --short HEAD          # = the main SHA you meant to ship
docker compose ps                                  # app + sidekiq freshly Up, db/mongo/redis healthy
curl -sk -o /dev/null -w '%{http_code}' https://<APP_HOST>/users/sign_in   # 200
docker compose exec -T app bundle exec rails runner \
  'Apartment::Tenant.switch!("cases"); puts Client.unscoped.count'          # counts unchanged
```

Also confirm the deploy log's encryption stages: every tier `verify PASS`, and
`reencrypt_client_names … re-encrypted=0` on a routine redeploy.

## HTTPS / TLS

Public HTTPS is Dockerized **Caddy** (`proxy` compose profile): set `APP_HOST` in `.env`, point
DNS at the box, open 80/443 in the security group, then
`docker compose --profile proxy up -d caddy`. Caddy auto-provisions and renews Let's Encrypt
certificates. The pilot box serves `https://cases.<ip-dashed>.nip.io` this way; a real domain is
an `APP_HOST` + DNS change, no code. Setting `APP_HOST` turns Rails host authorization on.

## Databases

- **Postgres major upgrades** are dump/restore, not in-place image swaps (the 9.6→17 migration
  playbook); the data volume must match the image major version.
- **Mongo major upgrades**: fresh volume + `mongodump`/`mongorestore` (the 6.0→8.0 rung), or
  in-place via the stepwise FCV ladder. Take the dump *before* touching the volume.
- **Backups**: take a `pg_dumpall` + `mongodump` into `~/backups/<label>/` before any deploy
  that migrates data or changes encryption schemes. Daily EBS snapshots are the box-level
  baseline per `SECURITY.md`.
- **Tenant export ("give the org their data back", POAM-014)**:
  `docker compose exec -T app bundle exec rake export:tenant TENANT=<short_name>
  EXPORT_PASSPHRASE=<phrase>` → a tar.gz(.enc) under `tmp/exports/` in the container: the
  tenant's schema dump (`pg_restore`-able), its Mongo history/audit slices, every upload its
  rows reference, and a checksummed manifest. Copy it out with `docker compose cp`, hand it
  off out-of-band, then delete it — the bundle holds decrypted PII. Every run writes a
  `record_exported` AccessLog.

## Scheduled jobs (host cron)

`bootstrap.sh` installs `config/schedule.rb` into the **host** crontab on every deploy
(`docker compose run --rm app bundle exec whenever | crontab -` — it REPLACES the ubuntu user's
crontab, which this deploy owns). Every job shells into the app container, so the host needs no
Ruby; output appends to `~/oscar/log/cron.log` (retention pipeline) and `~/oscar/log/whenever.log`
(reminders/reports). Inspect with `crontab -l`.

The weekly retention pipeline (POAM-015, archive-gated): Sunday 02:00 UTC `retention:archive`
(access_logs at 90d, versions + Mongo histories at 1095d) → 02:30 `retention:verify_archive`
(sha256 + recount; exits 1 on mismatch) → 03:00 the three `CONFIRM=1` purges, each of which
**refuses in code** unless its window has a verified archive and deletes at the manifest's cutoff.
Archives + `manifest.json` live on the persisted `archives` Docker volume (`/app/archives`,
`ARCHIVE_DIR`) — on the encrypted EBS root, covered by snapshots; copying them to the WORM tier
remains the infra hand-off (`docs/compliance/audit-retention.md` §3).

## Enforcement flags (the flip runbook)

The three Phase-5 flags — `enforce_authorization` (AC-3), `enforce_least_privilege` (AC-6),
`enforce_tenant_boundary` (SC-7) — have been **ON as the production default since 2026-07-26**
(`config/environments/production.rb`), flipped after the shadow-window review recorded **zero**
divergence events all-time. Resolution order per request: the tenant's persisted
`EnforcementSetting` row (the audited `/admin/enforcement_settings` panel) → else the environment
default. Rollback, softest first: panel → "Shadow (off)" or "Use system default" (per-tenant,
audited, next-request effect); console escape hatch
`EnforcementSetting.instance.update!(<flag>: nil)` inside the tenant; or revert the production.rb
block (deploy).

**The enforcement window (owner policy):** any flip that changes what staff can see or must do is
**announced before it lands**, and account-affecting enforcement waits for setup time. In
particular **`require_mfa` stays OFF** until every staff account has had time to enroll its auth
of choice (TOTP or passkey) — new-account onboarding includes MFA enrollment *before* the org
flips `require_mfa`. (By design `require_mfa` is an enroll-*nudge*, never a hard block — login,
the enrollment page, and the panel stay reachable — but the window policy stands regardless.)

## Containment (incident response)

Per `docs/compliance/policies/incident-response.md`: to contain, stop the app tier
(`docker compose stop app sidekiq`) — the data stores keep running for forensics; to isolate
harder, close 80/443 in the security group (SSM access is independent of the web ports).
Do **not** run retention purges during an incident. Redeploy/rollback is `bootstrap.sh` at a
pinned SHA (`BRANCH=<tag-or-branch> bash bootstrap.sh`).

## Tenant operations

Tenant schema changes ship through `rake apartment:migrate` (bootstrap runs it). Creating a
tenant is a console operation:
`Organization.create_and_build_tanent(short_name: 'sub', full_name: '...')` — the method name's
spelling is historical. The subdomain label must match `APP_HOST` routing.
