# Production box: resettlement flavor (SLO for HOME)

The first CaseLight **production** deployment. One server per flavor; same-flavor
orgs share a box as separate tenants. Companion docs: `OPERATIONS.md` (day-to-day
runbook, flavors, email), `SECURITY.md` (the data-handling baseline that gates
real client records), `docs/compliance/` (SSP, POA&M, HIPAA gap analysis).

## Inventory (us-east-2, account 934629276480)

| Thing | Value |
|---|---|
| Instance | `i-0732d5e55f96ec188` — t3.large (2 vCPU / 8 GB), Ubuntu 24.04 |
| Volume | 100 GB gp3, **encrypted at rest** |
| Elastic IP | `3.131.51.173` |
| Security group | `sg-0fc615fd657d804cb` — inbound **80/443 only** (no 22; admin access is SSH-over-SSM) |
| IAM instance profile | `IAMOscar` (SSM Session Manager) |
| Admin access | `ssh slo4home '<cmd>'` (alias in `~/.ssh/config`, ProxyCommand → SSM) |
| Hostname | `slo4home.lighthousent.org` (A → the Elastic IP) |
| Flavor / tenant | `FLAVOR=resettlement`, tenant `slo4home` ("SLO for HOME"), `SEED_DEMO=false` |
| Repo access | read-only GitHub deploy key `caselight-resettlement-prod` |
| Backups | AWS Backup plan `caselight-daily` → vault `caselight`, 09:00 UTC daily, 35-day retention, selects EC2 tagged `Backup=daily` |

The demo box (`i-0b045f7125306f0b5`, youth flavor, `cases.18-225-4-220.nip.io`) is
NOT in the backup plan — it holds synthetic data only and is rebuildable from
`bootstrap.sh` + seeds. Tag it `Backup=daily` if that changes.

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
  falls through to the `public` schema, whose root is `organizations#index` — an
  UNAUTHENTICATED page that lists every organization on the box. Keeping the apex
  on the marketing site means that page is never reachable.
* `config.action_dispatch.tld_length` is derived from `APP_HOST` in
  `config/environments/production.rb`; no manual tuning needed.

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
2. **DPA + CMIA addendum** signed with the org (2026-08-04 decision: the
   operative regime is the California Confidentiality of Medical Information
   Act, not HIPAA — see `docs/compliance/cmia-gap-analysis.md`). Accepting the
   AWS Business Associate Addendum in AWS Artifact is **optional** outside a
   HIPAA chain. Open CMIA items that gate real data: data residency (G1) and the
   confidential-health form for AB 352 categories (G2).
3. Encryption keys backed up off-box (above).
4. One **restore drill** completed on this box (snapshot → restore → verify a
   decrypted field reads correctly).
5. MFA enforced for staff accounts; the `require_mfa` enforcement flag reviewed
   in Security Enforcement.
6. Admin account seeded for the org, demo/synthetic data confirmed absent
   (`SEED_DEMO=false`; the tenant is created empty apart from taxonomy seeds).

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
* **Flavor lock**: youth surfaces (schools, youth seeds, `aeries:sync`) refuse to
  run here — the routes don't even resolve on a resettlement box.
* **Backups**: recovery points land in vault `caselight`. Verify with
  `aws backup list-recovery-points-by-backup-vault --backup-vault-name caselight`.

## Hermes agent handoff notes

The maintenance agent for this box should know:

1. **Deploy = rerun `bootstrap.sh` detached**, then poll by log/state — `pgrep`
   matches the launch wrapper, so poll the log, not the process.
2. **Seeds do not re-run on deploy** (stamp gates). Taxonomy changes need the
   explicit rake above; flag it rather than removing stamps.
3. **7c reencrypt / backfill stages run every deploy** — they must be idempotent.
   Verify names read back with correct CASE, not merely non-blank (the 2026-07
   incident NULLed name ciphertext, and the fix-up lowercased display names).
4. **Backup verification** = a recovery point newer than 24h in vault `caselight`
   AND the nightly in-box dump present. Report both.
5. **Never** `git push` from the box: the deploy key is read-only by design.
6. Access is SSM only; both boxes have port 22 closed.
