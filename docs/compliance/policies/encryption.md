# Encryption Policy — CaseLight

_NIST 800-53: SC-8, SC-12, SC-13, SC-28, SC-28(1). SOC 2: C1.1. Owner: the operating nonprofit /
maintainer. Review: annually or on any key-management or data-store change. Full narrative:
`encryption-at-rest.md`._

## Purpose
Protect PII in transit and at rest with cryptography, keep key management honest about the pilot-vs-
production distinction, and never let a secondary store become a plaintext shadow of the encrypted
primary.

## Policy

1. **In transit (SC-8).** All external traffic is HTTPS: the app sets `force_ssl` + HSTS and trusts a
   TLS-terminating reverse proxy (Caddy / Let's Encrypt). **Status:** documented and code-ready;
   Caddy is **live on the pilot box** (Dockerized, `proxy` compose profile, auto-renewing
   Let's Encrypt; see `OPERATIONS.md`). SSM remains the only shell path — no public SSH.
   Standing up TLS is a production gate (`ssp.md` §5). Internal service ports (PG/Mongo/Redis) are not
   network-exposed.
2. **At rest — field-level (SC-28/SC-28(1)).** Sensitive PII columns are encrypted with **ActiveRecord
   Encryption** in five tiers (Tiers 1–5, all merged): client names, narratives, address/location,
   staff account PII, and custom-form JSONB values. Deterministic where equality lookup is required
   (names, staff email), non-deterministic otherwise. The plaintext never lands in the primary
   Postgres columns, SQL logs, or `EXPLAIN`.
3. **At rest — history stores (SC-28(1)).** The change/history stores (paper_trail `versions`, Mongo
   `*_history`) are **redacted at the source** so they hold no plaintext copy of the encrypted fields
   (Phase 6; POAM-SC28-HIST). A drift-guard spec fails CI if a new `encrypts` field is not also
   skipped from versions.
4. **At rest — disk (inherited).** EBS volume encryption is a defense-in-depth layer beneath the
   field-level encryption, and is the **sole** layer for the documented plaintext residuals
   (`Client.date_of_birth`, `users.pin_number`, slug/org-code — see `encryption-at-rest.md` for why
   each is a locked decision).
5. **Uploaded documents.** Stored on the encrypted volume; served only through the authorized
   download controller (never raw static). File bytes are protected by that authorization + disk
   encryption (not field-encrypted).
6. **Key management (SC-12) — the pilot/production line.** In the pilot, AR-Encryption keys are
   **derived from `secret_key_base`** — acceptable only because the box holds synthetic data. **Before
   real client data (hard gate):** supply independent, **KMS-managed keys via ENV** (not derived), and
   do **not** set `support_unencrypted_data=false` until every tenant is backfilled and
   `encryption:verify` passes across every tier.
7. **Algorithms (SC-13).** Cryptography is the Rails/ActiveRecord Encryption default (AES-256-GCM);
   no custom crypto.

## Enforcement anchors
`config/initializers/active_record_encryption.rb`, `lib/tasks/encryption.rake` (`ENCRYPTION_TIERS`,
`backfill`/`verify`), `app/models/concerns/redacted_update_versions.rb`,
`app/classes/history_pii_filter.rb`, `app/controllers/downloads_controller.rb`,
`config/environments/production.rb` (force_ssl). See `encryption-at-rest.md`,
`history-store-sc28-poam.md`, `pii-inventory.md`, and `ssp.md` §3 (SC rows).
