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
- **Tier-5 search sidecar (POAM-024, step 7d)** — `properties_search:backfill CONFIRM=1` then
  `properties_search:verify` run on **every** deploy, after the encryption stages and before
  `up`. The backfill is a diff-sync (insert missing / delete stale, nothing else), so a routine
  redeploy MUST log `added=0 removed=0`; a non-zero delta means entries drifted outside the
  write path — `verify` will name the drifted records (values-free) and non-zero-exits, halting
  the deploy. The sidecar rows are derived data: a full rebuild is always safe
  (`properties_search:backfill CONFIRM=1` after any manual surgery, then re-verify).

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
  baseline per `SECURITY.md`. **The recovery unit is dumps + `.env` (or an EBS snapshot) — never
  dumps alone**: the AR-Encryption keys derive from the box's generated `SECRET_KEY_BASE`, so a
  dump set without its `.env` is ciphertext-locked. Encrypt any dump set that leaves the box
  (`openssl enc -aes-256-cbc -pbkdf2`, the export:tenant primitive); on-box sets rest on the
  encrypted EBS volume.
- **Restore (drilled 2026-07-26 — `docs/compliance/drills/`)**: throwaway stores on the compose
  network — `docker run -d --name drill-pg --network oscar_default -e POSTGRES_PASSWORD=drill
  postgres:17` (+ `drill-mongo` on `mongo:8.0`), then
  `docker exec -i drill-pg psql -U postgres -f - < pg_dumpall.sql` and
  `docker exec -i drill-mongo mongorestore --archive < mongodump.archive`, then a one-off app
  container with `DATABASE_HOST=drill-pg HISTORY_DATABASE_HOST=drill-mongo` running the evidence
  checks (counts == baseline; a Tier-4 value decrypts to its EXACT live value; Mongo collections
  non-empty), then `docker rm -f drill-pg drill-mongo`. For disaster recovery to a NEW box, swap
  the drill stores for the real compose stores before `up`, with the escrowed `.env` in place.
  Re-drill after any major schema/encryption change, and at least quarterly.
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

## Flavors (one server = one vertical)

Each server runs ONE flavor — `FLAVOR=resettlement | youth` in `.env` — which selects
the locale overlay (`config/flavors/<FLAVOR>/*.yml`, labels/vocabulary) and which
taxonomy `rake flavor:seed` plants (programs, forms, lists, assessment domains). The
value is whitelisted at boot: a typo stops the app with a clear error instead of
silently rendering base labels.

**Flipping the demo box** (the supported iteration workflow):
1. Edit `~/oscar/.env`: set `FLAVOR=youth` (and `SEED_DEMO=true` if you want the
   flavor's synthetic demo records — demo boxes ONLY, never production).
2. Rerun `bootstrap.sh`. The new flavor's seed stamp (`.flavor_seeded.youth`) is
   absent, so its taxonomy seeds; labels change at the restart.
3. Flip back the same way. Note: a flip does NOT remove the other flavor's seeded
   rows from the tenant — labels and *new* seeds change; a truly clean flip means a
   fresh tenant.

**Seed stamps.** `flavor:seed` is gated by `.flavor_seeded.<FLAVOR>` (and demo data by
`.flavor_demo_seeded.<FLAVOR>`) because seeding is NOT operator-safe to rerun blindly:
`seed_domains` destructively reconciles assessment domains against its keep-list, and
`seed_taxonomy` reverts any hand-edits made to seeded forms in the admin UI. To
deliberately re-apply an updated taxonomy: `rm .flavor_seeded.<FLAVOR>` and rerun
bootstrap (or `docker compose run --rm -e TENANT=<tenant> app bundle exec rake
flavor:seed`) — review what changed in the flavor's rake first.

Youth boxes should also set `ASSESSMENT_MIN_INTERVAL_DAYS=84` (12-week SEL pre/post
cadence). Unset preserves the legacy 6-calendar-month rule exactly — note that
6 months ≠ 180 days, so leave it unset on resettlement boxes rather than "equivalent"
day counts.

What the youth flavor contains and why: `docs/YOUTH-FLAVOR.md`. The Casebook
migration for the youth production box (audit → dry run → triple-gated import):
`docs/casebook-mapping.md`.

## Email (SMTP) and the client-direct reminder flip

Outbound mail is AWS SES over SMTP (`config/environments/production.rb`), driven by three
`.env` values on the box: `SENDER_EMAIL` (must be an SES-verified sender; empty/`nil` =
unconfigured), `AWS_SES_USER_NAME`, `AWS_SES_PASSWORD`. Until all three are real:

- **Staff reminder crons** (`Task.upcoming_incomplete_tasks`, overdue notifies) run and
  fail visibly at SMTP connect — unchanged, known state since go-live.
- **Client-direct reminders (data-task batch D6) stay OFF** — `ClientMessaging.enabled?`
  is the feature flip, and it is false unless a real sender AND both SES creds exist.
  There is no separate toggle: configuring SMTP IS the flip. Once flipped, the daily
  due-tomorrow cron also emails each **consented** client (`clients.notify_consent`,
  default false, set with the client's email on the individual form). Bodies are
  values-lean: appointment count + times only — no task names, no case content.

To flip: set the three values in `~/oscar/.env`, `docker compose up -d` (env re-read),
then verify `ClientMessaging.enabled?` via the runner and send yourself a test:
`docker compose exec app bundle exec rails runner "puts ClientMessaging.enabled?"`.

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
