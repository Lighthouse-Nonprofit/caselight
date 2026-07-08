# CaseLight — Compliance & Security Program

CaseLight is being hardened toward **FedRAMP Moderate** (NIST SP 800-53 Rev. 5 Moderate baseline) and
**SOC 2** (Trust Services Criteria: **Security + Confidentiality + Privacy**). This directory holds the
application-layer compliance artifacts. Infrastructure/AWS controls (volume encryption, network isolation,
WAF, backups/DR, WORM log storage, KMS/Secrets Manager) are **inherited** and documented with the deployment.

## Why
The system handles among the most sensitive PII categories that exist — refugee/asylee immigration status
and documents, minors' records, health and mental-health needs, government IDs. The bar is set accordingly.

## Roadmap (phased; see `~/.claude/plans` / the approved hardening plan)
- **Phase 0 — Secure SDLC + CI pipeline** *(in progress)*: SAST (Brakeman), dependency CVE scanning
  (bundler-audit), secret scanning (gitleaks), Dependabot — all gating every PR. This doc set seeded here.
- **Phase 1** — transport/headers/secrets baseline (force_ssl, secure_headers, secure cookies, credentials).
- **Phase 2** — auth hardening (MFA, lockout, throttling, idle timeout, password policy).
- **Phase 3** — audit & access logging (READ-access logging, structured logs, retention).
- **Phase 4** — encryption at rest for PII (ActiveRecord Encryption).
- **Phase 5** — authorization hardening + sensitive-field access control. *(complete; enforcement
  flags shadow-first, flipped per environment after AccessReview windows)*
- **Phase 6** — privacy & data lifecycle (retention/deletion, export, PII inventory). *(complete at
  the application layer, 2026-07: history-store redaction + one-time scrub [POAM-SC28-HIST],
  retention purges + policy, guarded/audited deletion, authorized upload downloads
  [POAM-SC28-UPLOADS], AC-2(3) inactive-account lifecycle, subject-access export, this inventory —
  plus the sidekiq-7/Redis-7 remediation closing the last High dependency findings)*
- **Phase 7** — SSP, control matrix, remaining policies, evidence automation.

## Artifacts
- `vulnerability-poam.md` — Plan of Action & Milestones: known findings + remediation schedule.
- `pii-inventory.md` — where PII lives, how each location is protected, how it leaves the system (Phase 6).
- `encryption-at-rest.md` / `history-store-sc28-poam.md` — SC-28 narrative + the history-store gap record.
- `audit-logging.md` / `audit-retention.md` — AU-family narrative + AccessLog retention policy.
- `policies/data-retention.md` — umbrella retention & deletion policy (Phase 6; the live client-record
  window is explicitly TBD and blocks production).
- (coming) `ssp.md` — System Security Plan: each 800-53 Moderate control → implementation / inherited / TBD.
- (coming) `control-matrix.md` — SOC 2 TSC → control → evidence pointer.
- (coming) remaining `policies/` — access control, audit, IR, change mgmt, encryption, vuln mgmt.

## How the pipeline enforces this (`.github/workflows/ci.yml`)
- **Brakeman** runs with `--compare config/brakeman_baseline.json` → fails only on **new** SAST findings.
- **bundler-audit** fails on any CVE **not** listed in `.bundler-audit.yml` (every ignore → a POA&M entry).
- **gitleaks** scans for committed secrets (`.gitleaks.toml` allowlists known synthetic placeholders).
- **Test suite** runs against PostgreSQL 17 / MongoDB 6 / Redis service containers.
- **Dependabot** opens weekly update PRs for gems, the Docker base image, and Actions.
