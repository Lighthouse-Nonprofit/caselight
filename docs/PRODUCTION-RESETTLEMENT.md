# Production box: resettlement flavor (SLO for HOME)

The first CaseLight **production** deployment. One server per flavor; same-flavor
orgs share a box as separate tenants. Companion docs: `OPERATIONS.md` (day-to-day
runbook, flavors, email), `SECURITY.md` (the data-handling baseline that gates
real client records), `docs/compliance/` (SSP, POA&M, and the **CMIA gap
analysis** — the operative privacy regime for this org, see the go-live gate).

## Inventory (**us-west-1**, N. California, account 934629276480)

| Thing | Value |
|---|---|
| Instance | `i-0b3c7efa80deb2212` — t3.large (2 vCPU / 8 GB), Ubuntu 24.04, AZ `us-west-1a` |
| Volume | `vol-02876154ec61e589c` — 100 GB gp3, **encrypted at rest** |
| Elastic IP | `204.236.131.38` |
| Security group | `sg-0e8fde8c8d43ac8a1` — inbound **80/443 only** (no 22; admin access is SSH-over-SSM) |
| IAM instance profile | `IAMOscar` (SSM Session Manager) — IAM is global, shared with the demo box |
| Admin access | `ssh slo4home '<cmd>'` (alias in `~/.ssh/config`, ProxyCommand → SSM, `--region us-west-1`) |
| Hostname | `slo4home.lighthousent.org` (A → the Elastic IP) |
| Flavor / tenant | `FLAVOR=resettlement`, tenant `slo4home` ("SLO for HOME"), `SEED_DEMO=false` |
| Repo access | read-only GitHub deploy key `caselight-resettlement-prod-usw1` |
| Snapshots | AWS Backup plan `caselight-daily` (`624811bc-406e-4681-91df-c5e7dc8aa39c`) → **us-west-1** vault `caselight`, 09:00 UTC daily, 35-day retention, selects EC2 tagged `Backup=daily` |
| In-box dumps | `ops/nightly_dump.sh` via the whenever crontab, 01:30 America/Los_Angeles → `~/oscar/backups`, 14-day rotation |

### Why N. California (data residency, CMIA gap G1)

This box was first built in us-east-2 (Ohio) and **rebuilt in us-west-1 on
2026-08-04, while it held zero client records**, so that California client
information is processed and stored in California. AB 352 requires a provider to
prevent out-of-state *disclosure* of confidential health information; keeping the
data plane in-state removes the argument entirely and is cheap to do before real
data lands. The Ohio instance, its Elastic IP, its security group and its (empty)
regional backup vault were destroyed — nothing was migrated, because there was
nothing to migrate.

Region-scoped things that had to be recreated rather than moved: the EC2 key
pair, the Elastic IP, the security group, and the **AWS Backup vault + plan +
selection** (AWS Backup is regional). The IAM instance profile and the SSM
service are global/regional-by-endpoint and needed no change. Other workloads in
the account stayed where they were — this relocation touched only the four
resources created for this box.

The demo box (`i-0b045f7125306f0b5`, youth flavor, `cases.18-225-4-220.nip.io`)
stays in **us-east-2** and is NOT in the backup plan — it holds synthetic data
only and is rebuildable from `bootstrap.sh` + seeds. It is also in a different
region from this plan now, so tagging it `Backup=daily` would not enrol it; a
us-east-2 plan would have to be created first.

The **youth production** box (still to be deployed) will hold California minors'
records too, so build it in **us-west-1** for the same residency reason.

## Hostnames and the tenant rule (read before touching DNS)

The app resolves the tenant from the **subdomain** (ros-apartment's subdomain
elevator). The leftmost label IS the tenant short_name AND the Postgres schema:

```
slo4home.lighthousent.org  →  tenant/schema "slo4home"
```

* **One A record per organization**, all pointing at the same Elastic IP. Adding
  a second resettlement org = create the tenant + add `org2.lighthousent.org`.
* Caddy (`Caddyfile`, `proxy` compose profile) serves exactly ONE `APP_HOST` and
  obtains its certificate over HTTP-01 — so port 80 must stay open and the record
  must be a plain A record (on Cloudflare: **DNS only**, not proxied). Serving
  several tenant hostnames means adding site blocks to the Caddyfile.
* **Never point the bare domain or `www` at a box.** A host with no tenant label
  resolves no tenant, so it lands in the `public` schema: sign-in there
  authenticates against a schema with no staff accounts, and tenant links built
  from `request.domain` come out wrong. Keep the apex on the marketing site.
* **`/` on a tenant hostname goes to that tenant's sign-in, not a picker.**
  `Organization` is an Apartment *excluded* model (`config/initializers/apartment.rb`),
  so `root 'organizations#index'` reads the public schema whatever tenant the
  elevator selected — it used to list every organization on the box to every org.
  Now a host that names a tenant redirects (signed out → its own sign-in, signed
  in → its dashboard) and only a host resolving NO tenant still shows the list.
  Pinned by `spec/requests/tenant_landing_spec.rb`.
* `config.action_dispatch.tld_length` is derived from `APP_HOST` in
  `config/environments/production.rb`; no manual tuning needed. Verified on this
  box: the root page's link resolves to
  `https://slo4home.lighthousent.org/dashboards`, i.e. `request.domain` is
  `lighthousent.org` and the tenant label survives — that link breaking to
  `slo4home.slo4home…` is the symptom of a bad `tld_length`.

### Enabling TLS (after the A record resolves)

```sh
ssh slo4home
cd ~/oscar
sed -i 's|^# APP_HOST=.*|APP_HOST=slo4home.lighthousent.org|' .env   # uncomment + set
docker compose up -d --force-recreate app sidekiq                    # host authorization
docker compose --profile proxy up -d caddy                           # ACME cert (~30s)
curl -sI https://slo4home.lighthousent.org/users/sign_in | head -1
```

## Secrets and key custody (the part that loses data if fumbled)

`.env` (mode 600, never committed) holds `DATABASE_PASSWORD`, `SECRET_KEY_BASE`
and the three **explicit** ActiveRecord encryption keys:

```
AR_ENCRYPTION_PRIMARY_KEY / _DETERMINISTIC_KEY / _KEY_DERIVATION_SALT
```

They are explicit (not derived from `SECRET_KEY_BASE`, which is the fallback in
`config/initializers/active_record_encryption.rb`) so that `SECRET_KEY_BASE` can
be rotated without orphaning every encrypted column.

> **The recovery unit is a database dump PLUS `.env` — or a whole-volume
> snapshot.** The 2026-07 restore drill proved dumps alone are ciphertext-locked.
> Copy the keys into the owner's password manager the day the box is built.

## Go-live gate (before ANY real client record)

`SECURITY.md` is the authority; the short version:

1. TLS live on the real hostname (Caddy cert issued, HTTP redirects to HTTPS).
   ✅ 2026-08-04: `https://slo4home.lighthousent.org/users/sign_in` → 200 over
   HTTP/2 with a Let's Encrypt cert, `http://` → 308, CSP enforcing,
   `robots.txt` = `Disallow: /`.
2. **DPA + CMIA addendum** signed with the org (2026-08-04 decision: the
   operative regime is the California Confidentiality of Medical Information
   Act, not HIPAA — see `docs/compliance/cmia-gap-analysis.md`). Accepting the
   AWS Business Associate Addendum in AWS Artifact is **optional** outside a
   HIPAA chain. Both technical CMIA items are now done: data residency (G1 — the
   box is in us-west-1) and the AB 352 confidential-health form (G2 — seeded
   `emergency_only`; run `slo4home:seed_taxonomy` once after deploying it, per
   Routine operations).
3. Encryption keys backed up off-box (above).
4. One **restore drill** completed on this box — `bash ops/restore_drill.sh`
   (below). ✅ passed 2026-08-04 on `i-0b3c7efa80deb2212`: ciphertext at rest →
   dump → scratch-database restore → byte-identical decrypt → deterministic name
   lookup → Mongo history archive.
5. MFA enforced for staff accounts; the `require_mfa` enforcement flag reviewed
   in Security Enforcement.
6. Admin account seeded for the org, demo/synthetic data confirmed absent
   (`SEED_DEMO=false`; the tenant is created empty apart from taxonomy seeds).

## Branding (the org's logo)

`Organization#logo` is the no-code branding hook: attach an image to the org row
and it becomes the sign-in page's logo (falling back to the CaseLight mark) plus
the 404/500 pages. SLO for HOME's logo was installed 2026-08-04 from their own
site. To replace it:

```sh
ssh slo4home 'cat > /tmp/logo.png' < new-logo.png
ssh slo4home 'cd ~/oscar && docker compose cp /tmp/logo.png app:/app/tmp/logo.png &&
  docker compose exec -T app bundle exec rails runner "
    org = Organization.find_by(short_name: %q(slo4home))
    org.logo = File.open(%q(/app/tmp/logo.png)); org.save!"'
```

png/jpg/gif only (`ImageUploader#extension_allowlist`). It is stored by
CarrierWave under `public/uploads/organization/logo/<id>/` on the **uploads
volume**, which is deliberately world-readable (`assets_uploads_guard.rb` allows
`/uploads/organization/` and denies every other upload path) because the login
page must render it before authentication. Note the volume is covered by the EBS
snapshot but NOT by `ops/nightly_dump.sh`, which dumps databases only — after a
volume-loss restore, re-attach the logo with the command above.

## Routine operations

* **Deploy**: `ssh slo4home 'cd ~/oscar && nohup ./bootstrap.sh > deploy.log 2>&1 &'`
  then poll the log (never leave it attached; SSM sessions drop). bootstrap is
  idempotent and re-execs itself if the sync changed the script.
* **Seeds are stamp-gated.** `flavor:seed` runs once per flavor
  (`.flavor_seeded.resettlement`); a redeploy does NOT re-run it. After a taxonomy
  change (e.g. the AOGP employment fields), run the specific rake by hand:
  `docker compose run --rm -e TENANT=slo4home app bundle exec rake slo4home:seed_programs`.
  Re-seeding blindly is not operator-safe — `seed_domains` destructively
  reconciles and `seed_taxonomy` reverts hand-edits in the admin UI.
  The **AB 352 confidential-health form** arrives the same way — after deploying
  it, once:
  `docker compose run --rm -e TENANT=slo4home app bundle exec rake slo4home:seed_taxonomy`,
  then confirm `Confidential Health Information` exists with sensitivity
  `emergency_only` (it is invisible in the UI without a break-glass grant, which
  is the point).
* **Flavor lock**: youth surfaces (schools, youth seeds, `aeries:sync`) refuse to
  run here — the routes don't even resolve on a resettlement box.
* **Backups**: two layers, and both must be checked.
  * Snapshots land in the **us-west-1** vault `caselight` —
    `aws backup list-recovery-points-by-backup-vault --backup-vault-name caselight --region us-west-1`.
  * In-box dumps land in `~/oscar/backups` nightly at 01:30 local; a dump under
    10 KB fails the script loudly rather than writing a useless file.
* **Restore drill**: `ssh slo4home 'cd ~/oscar && bash ops/restore_drill.sh'`.
  Safe on production — it restores into a scratch database and never touches the
  live one, then removes the scratch database, its synthetic canary row and its
  own dump files. Exit code = number of failed checks. Re-run it after any change
  to the encryption keys, the dump script, or the Postgres/Mongo major version.
  A `PASS` on "decrypted byte-identical" is the only acceptable result — a
  non-blank but case-changed read is a FAIL (that is exactly what the 2026-07
  incident looked like).

## Hermes agent handoff notes

The maintenance agent for this box should know:

1. **Deploy = rerun `bootstrap.sh` detached**, then poll by log/state — `pgrep`
   matches the launch wrapper, so poll the log, not the process.
2. **Seeds do not re-run on deploy** (stamp gates). Taxonomy changes need the
   explicit rake above; flag it rather than removing stamps.
3. **7c reencrypt / backfill stages run every deploy** — they must be idempotent.
   Verify names read back with correct CASE, not merely non-blank (the 2026-07
   incident NULLed name ciphertext, and the fix-up lowercased display names).
4. **Backup verification** = a recovery point newer than 24h in the **us-west-1**
   vault `caselight` AND a nightly in-box dump newer than 24h in `~/oscar/backups`
   (`log/backup.log` records `pg=…B mongo=…B`). Report both; a missing dump with a
   healthy snapshot is still a finding, because the snapshot cannot restore one
   table.
5. **This box lives in us-west-1** and the demo box in us-east-2. Every `aws` call
   needs the right `--region`; a "not found" is usually the wrong region, not a
   deleted resource.
6. **Never** `git push` from the box: the deploy key is read-only by design.
7. Access is SSM only; both boxes have port 22 closed.
8. `ops/restore_drill.sh` is the sanctioned way to prove backups are *usable*.
   Run it on request or after a key/version change — not on a schedule, since it
   writes a canary row to the live tenant for the length of the drill.
