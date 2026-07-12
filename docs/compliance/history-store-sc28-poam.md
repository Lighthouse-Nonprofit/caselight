# History-Store Encryption-at-Rest Gap — POA&M (SC-28)

_FedRAMP Moderate (SC-28 / SC-28(1)) + SOC 2 (Confidentiality C1.1). Owner: Lighthouse Nonprofit
Technologies. Last reviewed: Phase 4 close-out._

Companion to [`encryption-at-rest.md`](encryption-at-rest.md) (the SC-28 control narrative) and
[`vulnerability-poam.md`](vulnerability-poam.md). This entry tracks the **one residual SC-28 gap that
Phase 4 deliberately did not close**: the change/history stores hold plaintext copies of the same PII
that the primary Postgres columns now encrypt.

## POAM-SC28-HIST — Plaintext PII in the history stores

| Field | Value |
|---|---|
| **ID** | POAM-SC28-HIST |
| **Control** | SC-28 (Protection of Information at Rest), SC-28(1) (cryptographic protection) |
| **Severity** | Medium (demo box, synthetic data) / **High** (must close before real data) |
| **Status** | **CLOSED (2026-07-12)** — code merged Phase 6 (#89 paper_trail redaction, #90 Mongo snapshot filter, #98 one-time scrub); dev scrub executed + verified 2026-07-07 (441 version rows, 43 ClientHistory docs); **box scrub executed + verified at the 2026-07-12 production deploy** — closure evidence below. |
| **Discovered** | Phase 4 (encryption-at-rest) close-out review |

### The gap

Phase 4 encrypts PII **in the primary Postgres tables** (Client, User — see the Tier 1–4 inventory in
`encryption-at-rest.md`). Two **secondary** stores keep their own copies of those same values and were
**not** brought under encryption:

1. **MongoDB `*_history` models** — `ClientHistory` and its embedded children
   (`agency_client_history`, `case_client_history`, `case_worker_client_history`,
   `client_custom_field_property_history`, `client_family_history`,
   `client_quantitative_case_history`), plus `task_history`, `case_worker_task_history`,
   `client_history_association`. `Client` fires `after_save :create_client_history`, which calls
   `ClientHistory.initial(self)` and stores **`client.attributes`** — the full plaintext attribute
   hash, including `given_name` / `family_name` / `local_given_name` / `local_family_name` and the
   Tier 1/2 narrative & address fields — into the Mongo `object` Hash field. Mongo is a **single shared
   database** tenant-scoped only by a `tenant` field + `default_scope` (per the audit-logging narrative);
   AR Encryption does not reach it.

2. **paper_trail `versions` table (Postgres, per-tenant via Apartment)** — `Client` (and ~20 other
   models) declare `has_paper_trail` with no `skip:`/`only:` filter, so every create/update/destroy
   serializes the **full object** (and the changed columns) into `versions.object` /
   `versions.object_changes`. AR Encryption operates at the attribute read/write boundary of the
   *source* model; paper_trail serializes the model's attributes at the time of the change, capturing
   **plaintext** in the version row. The `versions` table is **not** encrypted at the column level.

Net effect: an attacker (or a backup/disk thief) who can read the Mongo data directory or the Postgres
`versions` table recovers the very PII that the primary `clients` / `users` columns now protect. **SC-28
is therefore not satisfied for the data as a whole** — only for the primary tables.

### Why it is acceptable for THIS box (and only this box)

This is the **synthetic-data demo/pilot box** (`SECURITY.md` hard rule: no real client records here).
The history stores contain only fabricated names/addresses. The residual exposure is therefore of
synthetic data, and the underlying disk is covered by the **inherited** infrastructure control
(EC2 EBS volume encryption at rest). Accepting the gap here does not put any real subject at risk.

### Recommended remediation (pragmatic path)

**For the demo box (now): accept, documented, with the infra disk-encryption as the compensating
control.** No code change required to ship Phase 4. This POA&M is the record of that decision.

**Recommended fix to schedule BEFORE real data (preferred option — redact at the source):**

- **paper_trail:** add an explicit allow/deny list so encrypted PII never enters a version row, e.g.
  `has_paper_trail(skip: %i[given_name family_name local_given_name local_family_name <tier1/2 fields>])`
  on `Client` (and the analogous staff fields on any `User`/paper_trail model). `skip:` omits the
  attribute from BOTH `object` and `object_changes`. Trade-off: the change history can no longer show
  *what* a name changed from/to — acceptable, because the history's compliance purpose is *who changed a
  record when*, which the version metadata (whodunnit, event, created_at) still provides.
- **Mongo `*_history`:** stop mirroring the encrypted attributes into the `object` Hash — filter them
  out of the `client.attributes` snapshot in `ClientHistory.initial` (and the embedded
  `*.try(:attributes)` snapshots) so only non-PII / foreign-key association data is retained. Same
  rationale: the history's job is to record association/state changes over time, not to be a second
  plaintext PII store.

**Alternative options (heavier; choose if the history MUST retain the field values):**

- **Encrypt the history store.** For paper_trail, store ciphertext in the version payload (e.g. a
  custom serializer or an encrypted `object`/`object_changes` column) keyed to the same AR Encryption /
  KMS material. For Mongo, encrypt the `object` field (Mongoid field-level encryption or client-side
  field-level encryption). Higher complexity; reintroduces key-management surface in two more places.
- **Accept-with-disk-encryption (demo only).** What we are doing now — explicitly NOT sufficient once
  real records exist.

### Hard gate for the real-data host

The future multi-tenant **real-data** host MUST NOT carry this gap. Before any real refugee/asylee
record is entered, EITHER (a) redact the encrypted PII fields from paper_trail (`skip:`) and from the
Mongo `*_history` `object` snapshots (recommended), OR (b) encrypt both history stores with managed
keys. Disk-at-rest encryption alone does NOT satisfy SC-28(1) for production PII of this sensitivity
(immigration status, minors, health, government IDs — see `docs/compliance/README.md`). This gate is a
precondition of the `SECURITY.md` production sign-off.

### Closure evidence — box scrub + verify (production deploy, 2026-07-12)

Executed on the pilot box (rev 12dbab7a) via a `bootstrap.sh` redeploy, then the Phase-6 runbook
(dry-run, CONFIRM=1, both verifies). Verbatim output:

~~~
[history:scrub_versions] models: Client, ClientEnrollment, ClientEnrollmentTracking, CustomFieldProperty, Family, LeaveProgram, Partner, ProgressNote, User confirm=true
  tenant=cases REDACTED=396
  ClientHistory client_family_histories: matched=9 modified=9
  ClientHistory client_custom_field_property_histories: matched=9 modified=9
[history:scrub_client_histories] TaskHistory: top-level candidates=0 paths=14 confirm=true
  TaskHistory case_worker_task_histories: matched=5 modified=5

  tenant=cases PASS
[history:verify_versions] PASS -- no skip-listed keys remain.
  ClientHistory: PASS
  TaskHistory: PASS
[history:verify_client_histories] PASS -- no redacted paths remain.
~~~

Both stores verified plaintext-free on the production host; pre-scrub pg_dumpall + mongodump
snapshots retained on-box at `~/backups/pre-frontend-deploy-20260712-0437/`.
