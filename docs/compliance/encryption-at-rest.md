# Encryption at Rest for PII — Control Narrative

_FedRAMP Moderate (SC-28 / SC-28(1)) + SOC 2 (Confidentiality C1.1). Phase 4. Last updated: Phase 4
close-out._

This document maps CaseLight's field-level encryption-at-rest implementation to SC-28 and is the
companion to the [history-store POA&M](history-store-sc28-poam.md) (the one residual gap) and the
existing audit material in this directory.

## Shared-responsibility line

CaseLight is the **application** layer. Phase 4 adds **field-level (column) encryption** of sensitive
attributes via **ActiveRecord Encryption**, so the plaintext never lands in the primary Postgres
columns, the SQL logs, or `EXPLAIN` output. **Volume / disk encryption at rest** (EBS), key-store
hardware protection (KMS/HSM), and backup encryption are **inherited** from the deployment
infrastructure. SC-28 is satisfied at the application layer by the column encryption below; the
inherited disk encryption is a defense-in-depth layer beneath it (and the *only* layer for the data
called out under "Residual gaps").

## Key management

- AR Encryption keys live in `config/initializers/active_record_encryption.rb`:
  **derived from `secret_key_base` in dev/test/CI**, taken from **ENV in production**.
  Derived keys are acceptable on THIS box because it is the synthetic-data demo/pilot box; the
  real-data host MUST supply independent, KMS-managed keys via ENV (not derived).
- `support_unencrypted_data = true` is set **on purpose** (the migration window — lets already-written
  plaintext rows still read while the per-tenant backfill runs). **Do not flip it** until every tenant
  is backfilled across every tier; flipping early makes un-backfilled rows unreadable.
- Tier 4 uses the **same** AR Encryption keys (no new key system). Deterministic encryption was chosen
  over a `blind_index` sidecar (see the Tier 4 note below), so there is no separate blind-index master
  key to manage.

## What SC-28 now covers (Postgres primary columns)

Encryption is rolled out in **tiers**, each a registered entry in `lib/tasks/encryption.rake`
(`ENCRYPTION_TIERS`) with a per-Apartment-tenant backfill. Tiers 1–4 are **merged**.

| Tier | Model · fields | Scheme | Query impact | Status |
|---|---|---|---|---|
| **1** | Client narrative/free-text fields (+ Family, ProgressNote, FamilyNote/FamilyAlert, and `Case.exit_note` — the client-exit-narrative copy, POAM-012, added 2026-07-26) | **Non-deterministic** | no equality/substring on ciphertext | Merged |
| **2** | Client address / location fields | **Non-deterministic** | address fields pruned from advanced-search; in-memory sort where needed | Merged |
| **3** | `User.email` + staff `first_name`/`last_name`/`mobile` + `uid` | **Deterministic** (+ downcase on email/uid) | equality + unique email index survive; iLIKE/range/ORDER BY do not | Merged |
| **4** | `Client.given_name`/`family_name`/`local_given_name`/`local_family_name` + `original_*` display sidecars | **Deterministic + `ignore_case`** (`fixed: false`, `previous:` = the original deterministic scheme); sidecars non-deterministic | whole-name equality lookup, **case-insensitive** (`quick_name_search`; advanced search routed to `clients.id IN (?)` via the `*_like` scopes); substring search still dropped; name dropped from SQL ORDER (alphabetical sort moved in-memory); display case preserved via the `original_*` sidecars | Merged (re-keyed UX round 3 C1) |

**Tier 4 note — why deterministic, not blind_index.** The original (locked) design picked `blind_index`
for exact + prefix name lookup. Prefix lookup turned out to be **cryptographically impossible** over an
HMAC (changing any input byte changes the whole digest), so `blind_index` would only deliver **exact**
match — the same capability **deterministic** encryption already gives (and Tier 3 already uses for
staff names), while adding a second master-key system + four sidecar columns + a custom backfill. We
therefore use deterministic encryption.

**Tier 4 update (UX round 3 C1, 2026-07-22 — this note previously documented case-sensitive search
as an accepted limitation; that limitation is removed).** The name columns now use Rails'
`ignore_case:` deterministic encryption: the stored column is downcased ciphertext (so equality is
**case-insensitive**), display case is preserved in encrypted non-deterministic `original_*`
sidecar columns (Rails-native, not blind_index), and `deterministic: { fixed: false }` +
`previous: [{ deterministic: true }]` keep pre-migration ciphertext readable during rollout. The
`Client.quick_name_search` scope builds the first/last/full-name equality queries. Migration is
`rake encryption:reencrypt_client_names` (below). **Operational invariants (learned from the
2026-07-22 pilot-box incident — see `incidents/2026-07-22-tier4-backfill-data-loss.md`):** any
task that reads an encrypted attribute to write it back must use `read_attribute` (the
`ignore_case` *reader* prefers the sidecar and does not reflect the column); the backfill refuses
to overwrite a non-NULL stored value with a nil read; and the reencrypt task is idempotent **by
skipping** rows whose sidecars are already populated (a re-run must not round-trip a migrated row
— that lowercases the display sidecar).

**Tier 5 (JSONB) — MERGED** (PR #47; this paragraph previously said PENDING and had gone stale —
refreshed in Phase 6): the polymorphic custom-form `.properties` values on CustomFieldProperty,
ClientEnrollment, ClientEnrollmentTracking and LeaveProgram are encrypted **non-deterministically**
(jsonb → text + `attribute :json` + `encrypts`; the Hash read interface is preserved). The four
JSONB-SQL search builders were rewritten to in-Ruby decrypt-and-filter via
`AdvancedSearches::PropertiesFilter`. Backfill/verify ran per tenant (dev + the pilot box, all
tiers PASS). Register: `ENCRYPTION_TIERS` in `lib/tasks/encryption.rake`.

## Residual gaps (tracked, not silently accepted)

1. **History stores — REMEDIATED (Phase 6).** The Mongo `*_history` models and the paper_trail
   `versions` table used to keep plaintext copies of the encrypted fields. Closed by redaction at
   the source (paper_trail `skip:` lists + the forced values-free who/when versions, #89; the
   `HistoryPiiFilter` snapshot scrub, #90) plus a one-time in-place scrub + verify of pre-existing
   rows (`history_redaction.rake`, #98 — executed and verified on dev; the box run happens at the
   Phase-6 deploy). Status + closure evidence: **[POAM-SC28-HIST](history-store-sc28-poam.md)**.
   The full field-by-field map now lives in **[pii-inventory.md](pii-inventory.md)**.

2. **`Client.date_of_birth` — PLAINTEXT (locked decision).** DOB stays plaintext: the `Client.filter`
   date-of-birth `EXTRACT(MONTH/YEAR)` clause and DOB's role in age/range queries and reporting would
   break under deterministic-or-nondeterministic encryption. Documented residual; covered only by
   inherited disk encryption. Revisit for the real-data host (DOB is PII).

3. **`users.pin_number` — LEAVE PLAINTEXT (locked decision).** See the dedicated note below.

4. **`slug` / org `code` — PLAINTEXT (by design).** `friendly_id` slugs and short org/lookup codes are
   non-PII identifiers used in routing/joins and are intentionally not encrypted. `Client#name` /
   `#en_and_local_name` / `#local_name` operate on the **decrypted** attributes in Ruby and are
   unchanged by Tier 4 (they decrypt transparently, preserving original casing).

## Decision note — `users.pin_number` stays PLAINTEXT

**Decision:** do **not** encrypt `users.pin_number`. **No code change.**

**Rationale:**
- **Not an authenticator.** `pin_number` is a manual integer staff lookup/display code. It is **not
  used in any auth/login path** — confirmed across `app/views/users/_form`, `user_serializer`,
  `UserGrid` (integer filter + column), and `users/show`. It gates nothing.
- **Low entropy + openly displayed.** It is a short integer shown in the staff UI. **Deterministic**
  encryption of a low-entropy, openly-displayed value is **brute-forceable** (an attacker can encrypt
  every candidate integer and match ciphertexts) — i.e. ~zero real at-rest benefit.
- **Breaks functionality for nothing.** Encrypting it would break the `UserGrid` **integer** filter and
  force an integer→text column migration, for that ~zero benefit.
- **If it ever becomes an access PIN: HASH it, do not encrypt it.** Should `pin_number` ever be
  repurposed to gate access, treat it as a secret authenticator — store a salted one-way **hash**
  (bcrypt/Argon2), never reversible encryption — and remove it from all display/serializer/grid
  surfaces. Until then, plaintext is the correct, documented choice.

## Verification

Per-tier regression specs live in `spec/models/tier{1,2,3,4}_encryption_spec.rb` (tenant `app`; they
prove `encrypts`-declared, raw-ciphertext round-trip, the rewritten query/sort sites, and — for Tiers
3/4 — deterministic exact/case-sensitive equality lookup). They run in the CI non-feature suite. The
scheduler spec (`spec/schedule_spec.rb`), fixed in this close-out, is added to the same CI rspec command.
Each tier's deploy runs, per Apartment tenant: `db:migrate` + `apartment:migrate` →
`rake encryption:backfill TIER=N CONFIRM=1` → `rake encryption:verify TIER=N` → (after the tier
loop) `rake encryption:reencrypt_client_names CONFIRM=1`, which migrates legacy Tier-4 rows onto
the `ignore_case` scheme and populates the `original_*` display sidecars — without it, legacy
rows *render blank* (the `ignore_case` reader prefers the not-yet-populated sidecar). A routine
redeploy reports `re-encrypted=0` (idempotent by skipping). Tier 4's backfill is a
name-**search** blocker (not a login blocker) for un-backfilled rows; Tier 3's email backfill is a
login blocker and must precede login. Task-level regression specs:
`spec/lib/tasks/encryption_backfill_spec.rb`, `spec/lib/tasks/encryption_reencrypt_names_spec.rb`.
