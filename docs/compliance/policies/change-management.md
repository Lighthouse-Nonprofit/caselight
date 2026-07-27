# Change Management Policy — CaseLight

_NIST 800-53: CM-2, CM-3, CM-4, CM-5, SA-11. SOC 2: CC8.1. Owner: the operating nonprofit / maintainer.
Review: annually or on any change to the pipeline._

## Purpose
Every change to CaseLight is reviewed, tested, and security-scanned before it reaches `main` or the
deployed box — no direct-to-production edits, no unscanned dependencies, no silent authorization
changes.

## Policy

1. **Branch → PR → review → merge (CM-3).** All changes land via pull request against `main`. Branch
   protection requires review; the merge is a deliberate act (the AI assistant cannot self-merge —
   `--admin` bypass is a human action). Direct pushes to `main` are not the normal path.
2. **Gated CI on every PR (SA-11, CC8.1)** — `.github/workflows/ci.yml`, all blocking:
   - **Brakeman** SAST with `--compare` against the baseline — **fails the build on any NEW finding**
     and uploads the report artifact (the gate is enforced, not advisory).
   - **bundler-audit** — fails on any dependency CVE not explicitly ignored; **every ignore maps to a
     POA&M row** with a remediation plan (`vulnerability-poam.md`).
   - **gitleaks** — fails on committed secrets (`.gitleaks.toml` allowlists synthetic placeholders).
   - **RSpec CI subset** — models/serializers/decorators/helpers/mailers/requests/controllers/lib/
     services/views (+ schedule) against PG 17 / Mongo 8 / Redis 7 service containers.
3. **Baseline configuration (CM-2).** The authoritative stack is pinned in `ssp.md` §1 and the
   Dockerfile/compose files; the CI service containers match it. Dependency updates arrive via
   **Dependabot** (weekly, grouped) and are triaged per the vulnerability-management policy — major
   bumps get a dedicated branch with verification, never a blind merge.
4. **Security-configuration changes (CM-5).** The runtime enforcement flags (authorization,
   least-privilege, tenant-boundary, MFA/lockout/timeout/expiry, inactive-disable) are changed only
   through the **admin-only enforcement-settings control room**, and **every flip is audited**
   (`enforcement_flag_changed` AccessLog event with who/from/to). The flags shipped shadow-first and
   have been the **production default since 2026-07-26** (flipped after the AccessReview shadow
   review recorded zero divergences; the per-tenant panel remains the audited runtime override —
   flip runbook + enforcement-window policy in `OPERATIONS.md`).
5. **Migrations.** Schema changes are per-tenant: `db:migrate` + `apartment:migrate`; numbered to
   avoid collisions; verified on dev before the box.
6. **Deploy.** The box is redeployed by rerunning the idempotent `bootstrap.sh` (build, migrate,
   encryption backfill+verify, client-name reencrypt, up — see `OPERATIONS.md`). Deploys carry only
   reviewed, merged `main`. If the sync changes `bootstrap.sh` itself, the script re-execs its
   fresh copy exactly once (`BOOTSTRAP_REEXEC`) so new deploy stages run in the deploy that
   introduces them — this guard is load-bearing (its absence caused the 2026-07-22 incident,
   `../incidents/2026-07-22-tier4-backfill-data-loss.md`).
7. **Evidence integrity (drift guards).** Specs fail CI if code and the compliance docs diverge:
   `paper_trail_redaction_spec` (skip lists ⊇ encrypted attributes), `version_reify_yaml_spec`
   (YAML permitted classes), the `ENCRYPTION_TIERS` registry, `HistoryPiiFilter.scrub_keys_for`.

## Enforcement anchors
`.github/workflows/ci.yml`, `.github/dependabot.yml`, `.bundler-audit.yml`, `.gitleaks.toml`,
`config/brakeman_baseline.json`, `app/controllers/enforcement_settings_controller.rb`,
`bootstrap.sh`. See `ssp.md` §3 (CM/RA/SI rows) + `vulnerability-management.md`.
