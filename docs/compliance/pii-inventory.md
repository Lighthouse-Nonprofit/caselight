# PII Inventory — CaseLight

_FedRAMP Moderate: SC-28, RA-2 (categorization), SI-12. SOC 2: Confidentiality C1.1, Privacy P3/P4._
_Phase 6 deliverable. Owner: Lighthouse Nonprofit Technologies. Review: on any schema/store change,
and alongside the annual data-retention review (`policies/data-retention.md`)._

The authoritative map of where personally identifiable information lives in CaseLight, how each
location is protected, and how it leaves the system. Three code artifacts keep this document
honest — when they drift, CI fails before this page lies:

- `lib/tasks/encryption.rake` `ENCRYPTION_TIERS` — the encrypted-column registry (backfill/verify).
- `spec/models/paper_trail_redaction_spec.rb` — drift guard: every versioned model's `skip:` list
  must cover its `encrypted_attributes`.
- `HistoryPiiFilter.scrub_keys_for` — call-time derivation for the Mongo snapshot denylists.

## 1. PostgreSQL — per-tenant Apartment schemas (the primary store)

| Model | Fields | Category | Protection | Notes |
|---|---|---|---|---|
| Client | given/family/local_given/local_family_name | Identity | **Encrypted (Tier 4, deterministic + ignore_case)** | Whole-name equality search, case-insensitive (`quick_name_search`); no substring search by design. Each column carries an encrypted non-deterministic `original_*` display sidecar (also Tier 4) preserving case (UX round 3 C1) |
| Client | reason_for_referral, background, exit_note, rejected_note, relevant_referral_information | Narrative (health/protection context) | **Encrypted (Tier 1, non-det)** | Unqueryable by design |
| Client | current_address, school_name, house_number, street_number, village, commune, district, live_with | Address/location | **Encrypted (Tier 2, non-det)** | |
| Client | date_of_birth | Identity | **Plaintext (locked decision)** | Age/range/EXTRACT queries require it; protected by RBAC + disk encryption; revisit for the real-data host (`encryption-at-rest.md`) |
| Client | slug, code | Routing identifiers | Plaintext (by design) | FriendlyId routing + unique indexes; non-PII identifiers |
| Family | caregiver_information, case_history | Narrative | **Encrypted (Tier 1)** | |
| Family | address | Address | **Encrypted (Tier 2)** | |
| FamilyNote | note | Narrative (household context) | **Encrypted (Tier 1, non-det)** | Added UX round 3; paper_trail-redacted; reads access-audited |
| FamilyAlert | title, body | Narrative (safety/operational warnings) | **Encrypted (Tier 1, non-det)** | Added UX round 3; resolved-not-deleted; paper_trail-redacted; reads access-audited |
| Partner | address | Address | **Encrypted (Tier 2)** | contact_person_* remain plaintext-searchable (staff-entered org contacts) |
| User | email, uid, first_name, last_name, mobile | Staff identity/contact | **Encrypted (Tier 3, deterministic; email/uid downcase)** | email is the login key |
| User | pin_number | Staff identifier | **Plaintext (locked decision)** | Not an authenticator; excluded from the XLS export (Phase 6 U1); if it ever gates access: HASH it |
| User | encrypted_password, otp_secret, otp_backup_codes, tokens, reset/unlock tokens | Credentials | bcrypt / AR-encrypted (otp_secret) / hashed | Never serialized into versions (U2 skip) or history snapshots (U3) or exports (U9) |
| ProgressNote | response, additional_note | Narrative | **Encrypted (Tier 1)** | |
| CustomFieldProperty / ClientEnrollment / ClientEnrollmentTracking / LeaveProgram | properties (JSON) | Custom-form values (any category the org configures — health, immigration, income…) | **Encrypted (Tier 5, non-det)** | In-Ruby search; sensitivity-classified per form (Phase 5.2) |
| Case | exit_note | Narrative | **Encrypted (Tier 1, non-det)** | Point-in-time copy of the client's exit narrative, fanned to sibling active cases per-record via `update_columns` (POAM-012, closed 2026-07-26); paper_trail-redacted with carer_names/carer_address/support_note |
| versions (paper_trail) | object / object_changes | Change audit | **PII-redacted at write (U2) + one-time scrub (U4)** | Who/when/event + non-PII before/after only; retention via `retention:purge_versions` |

## 2. MongoDB — single shared database (tenant field + default_scope)

| Collection | Contents (post-Phase-6) | Protection | Retention |
|---|---|---|---|
| client_histories (+ embedded agency/case/case_worker/custom_field_property/family/quantitative histories) | ids / statuses / dates / association keys ONLY — `HistoryPiiFilter` strips encrypted attributes + staff credential/IP metadata at write (U3); pre-existing rows scrubbed (U4) | Tenant default_scope; write-only (no reader); purged on client destroy (U6) | `retention:purge_client_histories` (365-day floor) |
| task_histories (+ embedded case_worker histories) | Same contract; StaffMonthlyReport reads only completion_date/completed/user_ids | As above | As above |
| access_logs | Values-free event rows: ids/types + denormalized user_email (the one allowed identifier) | Append-only (raise on update/destroy); tenant default_scope | `audit:purge` — 90d online / ≥1yr WORM (`audit-retention.md`) |

## 3. Filesystem — `public/uploads` (Docker volume on the encrypted EBS root)

| Prefix | Contents | Serving |
|---|---|---|
| attachment/{file,image} | Progress-note documents; able-screening question images | **Authorized DownloadsController only** (U7); raw static requests 403 |
| custom_field_property/attachments | Custom-form documents (identity docs, leases, IEPs…) | Authorized + custom-field sensitivity gate (U7) |
| case_note_domain_group/attachments | Case-note documents | Authorized (record-level; domain-sensitivity residual = POAM-013) |
| form_builder_attachment/file | Enrollment/tracking/leave-program documents | Authorized + CFP sensitivity gate where applicable (U7) |
| assessment_domain/attachments | Assessment documents | Authorized + domain-sensitivity gate (Phase 5.3) |
| organization/logo | Org branding | Public by design (login page) |

File **bytes** and the CarrierWave `attachments` JSONB metadata column (filenames) are outside AR
Encryption — protected by the authorized serve path + inherited disk encryption. Files are removed
on record destroy (CarrierWave default, verified Phase 6).

## 4. Logs and exports

| Surface | PII posture |
|---|---|
| lograge request log | Values-free tags: request_id, user_id, tenant, remote_ip |
| AccessLog JSON lines | Same values-free contract (mirrors §2) |
| Client XLS / advanced-search exports | Ability-scoped + Phase-5.3 sensitivity-masked |
| Families/Partners/Users/ProgressNotes XLS | Ability-scoped (U1); pin_number excluded |
| Access-review CSV | Staff roster (deliberate AC-2(j) artifact; admin-only) |
| `privacy:subject_access_export` | One subject's records, allowlist-based; staff as ids; files by name; every run writes `record_exported` (U9) |
| `api/clients#compare` | Current-tenant duplicate check: minimal `{id, organization}` payload (no record values), name-field required, values-free `client_compare_probe` audit (**POAM-AC3-COMPARE closed 2026-07-26** — the cross-tenant loop is gone) |
| UserSerializer (`api`) | `pin_number` **removed** from the attribute list (POAM-016, closed 2026-07-19) |

## 5. Residual gaps (all tracked)

| Item | Where tracked |
|---|---|
| Client.date_of_birth plaintext | `encryption-at-rest.md` (locked; revisit for real-data host) |
| users.pin_number plaintext | `encryption-at-rest.md` (locked; hash-if-authenticator) |
| ~~cases.exit_note plaintext copy~~ | **POAM-012 — closed 2026-07-26** (encrypted Tier 1; see §1) |
| Case-note domain-group attachments lack per-domain sensitivity mapping | **POAM-013** |
| Tenant-level full data export (backup/portability) | **POAM-014** (deferred; inherited backups cover DR) |
| Purge auto-scheduling blocked on archive-verification gate | **POAM-015** |
| Assessment edit-form attachment link dead (guard-403'd; show page uses the safe route) | **POAM-013** note |
