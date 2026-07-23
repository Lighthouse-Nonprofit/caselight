# SOC 2 Control Matrix — CaseLight

_Trust Services Criteria in scope: **Security** (Common Criteria CC1–CC9), **Confidentiality** (C1),
**Privacy** (P-series). Application layer of a self-hosted deployment. Companion to `ssp.md` (the NIST
800-53 view) — this is the SOC 2 lens on the same control set. Last updated: Phase 7 (2026-07)._

**How to read this:** each row maps a TSC point of focus → CaseLight's control → the resolvable
**evidence** (code path, doc section, rake task, CI job, or spec). It is a **pointer index** — the
implementation detail lives in the SSP control tables and the narrative docs it cites, so the two
never drift. Run `rake compliance:evidence` for a machine-checked snapshot of the verifiable gates.
Inherited-infra responsibilities (physical, network, host, backups, WORM, KMS, TLS termination) are
in `ssp.md` §4 and are the operating entity's to attest, not the application's.

## CC1 — Control Environment
| TSC focus | CaseLight control | Evidence |
|---|---|---|
| CC1.1 integrity / documented commitments | The compliance program itself: phased hardening, this doc set, honest production gate | `docs/compliance/README.md`, `SECURITY.md`, `ssp.md` |
| CC1.4 competence / defined process | Change-management + secure-SDLC process | `policies/change-management.md`, `policies/vulnerability-management.md` |

## CC2 — Communication & Information
| CC2.1 internal information / audit trail | Access + change + security-event logging; reviewable per tenant | `audit-logging.md`; `app/models/access_log.rb` |
| CC2.2 / CC2.3 internal & external comms | Compliance framing for org/funder questions; source availability (AGPL) | `SECURITY.md` "compliance framing"; `README.md` |

## CC3 — Risk Assessment
| CC3.1 objectives / data categorization | RA-2 categorization → Moderate (special-category PII) | `ssp.md` §2; `pii-inventory.md` |
| CC3.2 risk identification | Vulnerability POA&M ledger; PII residual-gap table | `vulnerability-poam.md`; `pii-inventory.md` §residuals |

## CC4 — Monitoring
| CC4.1 ongoing evaluation | CI gates on every PR; reproducible evidence bundle | `.github/workflows/ci.yml`; `rake compliance:evidence` |
| CC4.2 deficiencies tracked & remediated | POA&M with severity/status/remediation; drift-guard specs fail CI | `vulnerability-poam.md`; `paper_trail_redaction_spec`, `version_reify_yaml_spec` |

## CC5 — Control Activities
| CC5.1–5.3 controls / technology / policy | The control set below + the policy pack | `policies/`, `ssp.md` §3 |

## CC6 — Logical & Physical Access
| TSC focus | CaseLight control | Evidence |
|---|---|---|
| CC6.1 logical access / least privilege | CanCanCan RBAC + field-level `SensitivityPolicy`; tenant isolation (Apartment schema-per-tenant + `TenantBoundary`) | `app/classes/ability.rb`, `sensitivity_policy.rb`, `app/controllers/concerns/tenant_boundary.rb`; `ssp.md` AC-3/AC-6 |
| CC6.1 credentials | Password policy (complexity/no-reuse), rate-limiting | `config/initializers/devise.rb`, `rack_attack.rb` |
| CC6.2 / CC6.3 registration / recertification | One user per staff; **AccessReview recertification report + CSV** (roles, MFA gap, disabled, caseload) | `app/controllers/access_reviews_controller.rb` |
| CC6.1 strong auth | MFA (TOTP) + passkeys (WebAuthn) | `config/initializers/two_factor.rb`, `webauthn.rb` |
| CC6.6 boundary protection | Security headers + CSP; force_ssl behind proxy; zero-inbound SG (inherited) | `config/application.rb`, `content_security_policy.rb`; `ssp.md` §4 |
| CC6.7 data-in-transit / restricted movement | TLS (Caddy — live on the pilot box / inherited); authorized-only file downloads; masked exports | `downloads_controller.rb`, `assets_uploads_guard.rb`; `ssp.md` SC-8 |
| CC6.7 credential/secret handling | Filtered params/logs; secrets in gitignored `.env`; gitleaks CI | `filter_parameter_logging.rb`; `.gitleaks.toml` |
| CC6.8 unauthorized software / integrity | Brakeman SAST gate; safe deserialization (no `eval`); CSP | `.github/workflows/ci.yml`; `app/classes/safe_version_value.rb` |

## CC7 — System Operations
| TSC focus | CaseLight control | Evidence |
|---|---|---|
| CC7.1 vulnerability detection | Brakeman + bundler-audit + gitleaks + Dependabot | `.github/workflows/ci.yml`, `.github/dependabot.yml` |
| CC7.2 anomaly monitoring | Security-event rows (login_failure / account_locked / access_denied) as detection signal | `audit-logging.md` CC7.2; `access_log.rb` |
| CC7.3 evaluation of events | Retained ≥90-day online AccessLog window; review indexes; shadow tables | `audit-retention.md`; AccessReview |
| CC7.4 incident response | Detection signal + documented IR process (named owners TBD before real data) | `policies/incident-response.md` |

## CC8 — Change Management
| CC8.1 change control | branch → PR → green CI → review; SAST/dep/secret gates; enforcement-flag control room admin-only + audited | `policies/change-management.md`; `enforcement_settings_controller.rb` |

## CC9 — Risk Mitigation
| CC9.1 risk mitigation / disruption | POA&M-driven remediation; retention/purge with floors; inherited backups/DR | `vulnerability-poam.md`; `policies/data-retention.md`; `ssp.md` §4 |
| CC9.2 vendor/dependency risk | Dependency CVE scanning + upgrade cadence | `policies/vulnerability-management.md` |

## C1 — Confidentiality
| TSC focus | CaseLight control | Evidence |
|---|---|---|
| C1.1 identify & protect confidential info | Field-level encryption at rest Tiers 1–5 (primary + history stores redacted); PII inventory | `encryption-at-rest.md`, `history-store-sc28-poam.md`, `pii-inventory.md` |
| C1.1 confidentiality in transit/serving | Authorized download controller + static-guard; masked datagrid exports | `downloads_controller.rb`; `ssp.md` AC exports |
| C1.2 disposal of confidential info | Guarded destroy + Mongo purge + retention purges (365-day floor); media sanitization | `policies/data-retention.md`; `ssp.md` MP-6 |

## P — Privacy
| TSC focus | CaseLight control | Evidence |
|---|---|---|
| P1/P2 notice & choice | Org-owned (out of app scope); synthetic-data pilot rule | `SECURITY.md` |
| P3 collection / P4 use, retention, disposal | PII inventory; retention policy (live-record window TBD-blocking); minimization in logs | `pii-inventory.md`, `policies/data-retention.md` |
| P4.2/P4.3 retention & disposal | Retention purges + deletion lifecycle; values-free audit | `lib/tasks/retention.rake`, `audit.rake` |
| P5 access (data-subject requests) | Per-client subject-access export (allowlist JSON, audited) | `lib/tasks/privacy.rake` (`privacy:subject_access_export`) |
| P6 disclosure / P7 quality / P8 monitoring | Change audit (paper_trail) for record quality; access audit for disclosure tracking; POA&M for monitoring | `audit-logging.md`; `vulnerability-poam.md` |

## Not-yet-satisfied (gates production with real data)
Tracked in `ssp.md` §5 + `vulnerability-poam.md`: KMS-managed encryption keys (SC-12), a production
TLS hostname (CC6.7 — TLS itself is live on the pilot box via Caddy/Let's Encrypt), the live
client-record retention window (P4 — TBD-blocking), a named-owner incident
plan (CC7.4), and confirmed inherited backups/WAF/network isolation. The AC-3/AC-6 enforcement flags
ship shadow-first and are flipped per environment after an AccessReview shadow-window review.
