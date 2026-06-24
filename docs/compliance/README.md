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
- **Phase 5** — authorization hardening + sensitive-field access control.
- **Phase 6** — privacy & data lifecycle (retention/deletion, export, PII inventory).
- **Phase 7** — SSP, control matrix, policies, evidence automation.

## Artifacts
- `vulnerability-poam.md` — Plan of Action & Milestones: known findings + remediation schedule.
- (coming) `ssp.md` — System Security Plan: each 800-53 Moderate control → implementation / inherited / TBD.
- (coming) `control-matrix.md` — SOC 2 TSC → control → evidence pointer.
- (coming) `policies/` — access control, audit, IR, change mgmt, data retention, encryption, vuln mgmt.

## How the pipeline enforces this (`.github/workflows/ci.yml`)
- **Brakeman** runs with `--compare config/brakeman_baseline.json` → fails only on **new** SAST findings.
- **bundler-audit** fails on any CVE **not** listed in `.bundler-audit.yml` (every ignore → a POA&M entry).
- **gitleaks** scans for committed secrets (`.gitleaks.toml` allowlists known synthetic placeholders).
- **Test suite** runs against PostgreSQL 17 / MongoDB 6 / Redis service containers.
- **Dependabot** opens weekly update PRs for gems, the Docker base image, and Actions.
