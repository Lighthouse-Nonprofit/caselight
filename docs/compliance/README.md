# CaseLight — Compliance & Security Program

CaseLight is hardened to the **FedRAMP Moderate** baseline (NIST SP 800-53 Rev. 5) and aligned to
**SOC 2** (Trust Services Criteria: **Security + Confidentiality + Privacy**) at the application layer.
This directory holds the application-layer compliance artifacts. Infrastructure/AWS controls (volume
encryption, network isolation, WAF, backups/DR, WORM log storage, KMS/Secrets Manager) are **inherited**
and documented with the deployment.

**Start here:** [`ssp.md`](ssp.md) is the anchor — system description, data categorization, the
application-layer control set with evidence pointers, the inherited-controls boundary, and the
residual-risk / production gate. [`../../SECURITY.md`](../../SECURITY.md) is the plain-language data-handling
posture + the production sign-off gate. The **application-layer program (Phases 0–7) is complete**; the
system is ready to operate on **synthetic data** under the pilot baseline. Real client data is a
**separate, deliberate gate** — see `ssp.md` §5.

## Why
The system handles among the most sensitive PII categories that exist — refugee/asylee immigration status
and documents, minors' records, health and mental-health needs, government IDs. The bar is set accordingly.

## Roadmap (phased) — **application layer COMPLETE (Phases 0–7)**
- **Phase 0 — Secure SDLC + CI pipeline** *(complete)*: SAST (Brakeman, gate fails on new findings),
  dependency CVE scanning (bundler-audit), secret scanning (gitleaks), Dependabot — all gating every PR.
- **Phase 1 — transport/headers/secrets** *(complete)*: force_ssl/assume_ssl, explicit security headers,
  CSP (report-only), secure cookies.
- **Phase 2 — auth hardening** *(complete)*: MFA (TOTP) + passkeys, lockout, throttling, idle timeout,
  password policy.
- **Phase 3 — audit & access logging** *(complete)*: AccessLog (read + security events), lograge,
  paper_trail change audit, retention.
- **Phase 4 — encryption at rest** *(complete)*: ActiveRecord Encryption, Tiers 1–5.
- **Phase 5 — authorization + sensitive-field access control** *(complete)*: RBAC + field-level
  sensitivity + break-glass; enforcement flags shadow-first, flipped per environment after AccessReview windows.
- **Phase 6 — privacy & data lifecycle** *(complete, 2026-07)*: history-store redaction + scrub
  [POAM-SC28-HIST], retention purges + policy, guarded/audited deletion, authorized upload downloads
  [POAM-SC28-UPLOADS], AC-2(3) inactive-account lifecycle, subject-access export, PII inventory — plus the
  sidekiq-7/Redis-7 remediation closing the last High dependency findings.
- **Phase 7 — SSP, control matrix, policies, evidence automation** *(complete, 2026-07)*: `ssp.md`,
  `control-matrix.md`, the full `policies/` set, and `rake compliance:evidence` + a Brakeman gate that
  actually fails on new findings.

Remaining work is the **production gate** (real client data), not application-layer controls: KMS-managed
keys, TLS in operation, the live-record retention decision, confirmed inherited backups/WAF/network
isolation, and a named-owner incident plan. See `ssp.md` §5 + `SECURITY.md`.

## Artifacts
- [`ssp.md`](ssp.md) — **System Security Plan** (the anchor): system description + pinned stack, RA-2
  categorization, the app-layer control set with status + evidence, inherited-controls appendix,
  residual-risk / production gate, evidence & verification, production-readiness statement.
- [`control-matrix.md`](control-matrix.md) — SOC 2 TSC (CC / C1 / P) → control → evidence pointer.
- `policies/` — [`access-control`](policies/access-control.md), [`audit`](policies/audit.md),
  [`incident-response`](policies/incident-response.md), [`change-management`](policies/change-management.md),
  [`encryption`](policies/encryption.md), [`vulnerability-management`](policies/vulnerability-management.md),
  [`data-retention`](policies/data-retention.md).
- `vulnerability-poam.md` — Plan of Action & Milestones: known findings + remediation schedule.
- `pii-inventory.md` — where PII lives, how each location is protected, how it leaves the system.
- `encryption-at-rest.md` / `history-store-sc28-poam.md` — SC-28 narrative + the history-store record.
- `audit-logging.md` / `audit-retention.md` — AU-family narrative + AccessLog retention policy.

## How the pipeline enforces this (`.github/workflows/ci.yml`)
- **Brakeman** runs with `--compare config/brakeman_baseline.json` and **fails the build on any new SAST
  finding** (a dedicated step parses `.new[]`; the report is uploaded as a CI artifact).
- **bundler-audit** fails on any CVE **not** listed in `.bundler-audit.yml` (every ignore → a POA&M entry).
- **gitleaks** scans for committed secrets (`.gitleaks.toml` allowlists known synthetic placeholders).
- **Test suite** runs against PostgreSQL 17 / MongoDB 8 / Redis 7 service containers.
- **Dependabot** opens weekly update PRs for gems, the Docker base image, and Actions.
- **`rake compliance:evidence`** bundles the read-only verifier outputs (encryption/history verify,
  break-glass smoke, retention report, bundle-audit) for a reproducible evidence snapshot / pre-deploy gate.
