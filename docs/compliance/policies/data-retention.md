# Data Retention & Deletion Policy — CaseLight

_FedRAMP Moderate: AU-11, SI-12, MP-6. SOC 2: Confidentiality C1.1–C1.2, Privacy P4.2–P4.3._
_Status: active for the synthetic-data pilot; the client-record retention row is **TBD and blocks
production** (see §2). Owner: Lighthouse Nonprofit Technologies. Review: annual, or on any change
to a data store or deletion path._

This is the umbrella retention policy the compliance README promised (`docs/compliance/README.md`,
Phase 6). The AccessLog-specific policy (`docs/compliance/audit-retention.md`) remains authoritative
for the audit store; this document incorporates it by reference.

## 1. Data categories and stores

| Category | Store | Contents (post-Phase-6) |
|---|---|---|
| Live client/case records | PostgreSQL, per-tenant Apartment schema | Encrypted PII (Tiers 1–5) + plaintext operational fields (status, dates, ids; DOB/slug per the documented exceptions in `encryption-at-rest.md`) |
| Change audit (who/what/when) | PostgreSQL `versions` (paper_trail), per-tenant | Values-free for PII fields (Phase-6 `skip:` redaction); full before/after for non-PII fields |
| Shadow history | MongoDB `client_histories` / `task_histories` (shared DB, tenant field) | Ids / statuses / dates / association keys only (Phase-6 `HistoryPiiFilter`) |
| Access & security-event audit | MongoDB `access_logs` (shared DB, tenant field) | Values-free event rows (ids, types, denormalized user_email) — governed by `audit-retention.md` |
| Uploaded documents | Filesystem `public/uploads` (Docker named volume on the encrypted EBS root) | Document bytes; served only through authorized download routes (Phase-6 uploads unit) |
| Request logs | lograge JSON (shipped off-box) | Values-free request metadata — retention is an infrastructure control |
| Backups | EBS snapshots (infrastructure) | **Inherited control** — encrypted snapshots; retention set with the hosting baseline |

## 2. Retention windows

| Category | Window | Basis / status |
|---|---|---|
| Live client/case records | **TBD — BLOCKS PRODUCTION.** Must be set with the org (and their legal/funder obligations) before any real record is entered. Refugee-resettlement records raise specific questions: immigration case files and minors' records may carry multi-year (or majority-age-plus) obligations. | `SECURITY.md` production gate explicitly requires this decision. The pilot runs synthetic data, so no window is in force yet. |
| `versions` (change audit) | **Proposed: 3 years** (owner to ratify) | Long enough for after-the-fact investigation + SOC 2 evidence; bounded so the per-tenant tables stop growing without limit. Floor: never below **365 days** (enforced in code). |
| Mongo `ClientHistory`/`TaskHistory` | **Proposed: 3 years** (owner to ratify) | Same rationale; post-redaction these carry association/state history only. Same 365-day code floor. |
| `AccessLog` | ≥ 90 days online / ≥ 1 year WORM archive | Existing policy — `audit-retention.md` (AU-11). |
| Uploaded documents | Follow the owning record (removed on record destroy via CarrierWave) + the live-record window above | Deletion path verified Phase 6. |
| Backups | Infrastructure baseline | Inherited; must not silently extend the live-record window (expired-data restores are handled by the deletion-path re-run on restore). |

## 3. Sanctioned deletion paths (the only ones)

| Store | Path | Guards |
|---|---|---|
| `versions` | `rake retention:purge_versions DAYS= [TENANT=] CONFIRM=1` | Dry-run default; **hard 365-day floor**; per-tenant iteration; batched `delete_all`; per-tenant counts printed for the archive reconciliation |
| Mongo histories | `rake retention:purge_client_histories DAYS= CONFIRM=1` | Dry-run default; same floor; cross-tenant `unscoped` (audit.rake idiom) with per-tenant breakdown |
| `AccessLog` | `rake audit:purge DAYS= CONFIRM=1` | Per `audit-retention.md` (90-day floor) |
| Live records | In-app destroy (CanCan-authorized; Client destroy guarded on associated cases/enrollments) → cascades to children + uploaded files (CarrierWave) + the record's Mongo history docs; the final destroy version (PII-free) is **kept** as deletion evidence | Phase-6 deletion-lifecycle unit; every destroy emits a values-free `record_destroyed` AccessLog event |
| Subject-access / erasure requests | Operator-run per the privacy rake (`privacy:subject_access_export`) + the in-app destroy path above | Logged; see Phase-6 export unit |

**None of the purges are scheduled.** The verified-archive-before-purge precondition
(`audit-retention.md` §4.2) is not yet code-enforced — until it is (tracked as a POA&M item),
every purge is a deliberate operator action: dry-run → reconcile counts against the archive →
`CONFIRM=1`. `rake retention:report` provides the read-only age-bucket evidence for reviews.

## 4. Legal hold / exceptions

If litigation, an audit, or a safeguarding investigation requires preserving records beyond (or
deleting ahead of) the windows above, the owner records the exception here (what, why, scope,
start/end) before any deviation runs. No exception mechanism exists in code by design — a hold is
an operational decision, and the purges' TENANT/DAYS parameters give the operator the needed
selectivity without building a bypass into the request path.

## 5. Review cadence

- Annually, and whenever a new data store, export surface, or deletion path is added.
- Each purge run's dry-run output + the `retention:report` snapshot are retained as evidence
  (SOC 2 CC7.2 / P4.3).
