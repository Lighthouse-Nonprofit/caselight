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
| **1** | Client narrative/free-text fields | **Non-deterministic** | no equality/substring on ciphertext | Merged |
| **2** | Client address / location fields | **Non-deterministic** | address fields pruned from advanced-search; in-memory sort where needed | Merged |
| **3** | `User.email` + staff `first_name`/`last_name`/`mobile` + `uid` | **Deterministic** (+ downcase on email/uid) | equality + unique email index survive; iLIKE/range/ORDER BY do not | Merged |
| **4** | `Client.given_name`/`family_name`/`local_given_name`/`local_family_name` | **Deterministic** (no downcase) | exact name lookup via equality (advanced search routed to `clients.id IN (?)` via the `*_like` scopes); **case-sensitive**; substring search dropped; name dropped from SQL ORDER (alphabetical sort moved in-memory) | Merged |

**Tier 4 note — why deterministic, not blind_index.** The original (locked) design picked `blind_index`
for exact + prefix name lookup. Prefix lookup turned out to be **cryptographically impossible** over an
HMAC (changing any input byte changes the whole digest), so `blind_index` would only deliver **exact**
match — the same capability **deterministic** encryption already gives (and Tier 3 already uses for
staff names), while adding a second master-key system + four sidecar columns + a custom backfill. We
therefore use deterministic encryption. Trade-off: name search is now **exact and case-sensitive** (no
`downcase:`, so the stored — and therefore displayed — casing is preserved; `downcase:true` would make
`Client#name` render lowercase everywhere). Case-insensitive name search would require the declined
`blind_index` sidecar; it is a documented, accepted limitation for the pilot.

**Tier 5 (JSONB) — PENDING (separate later workflow):** the polymorphic custom-form values in the
`.properties` JSONB columns (CustomFieldProperty et al.) are **not yet encrypted**, and the custom-form
search over them is untouched. Sensitive PII entered through custom fields is therefore **not** covered
by SC-28 until Tier 5 lands. Tracked as the next encryption workflow.

## Residual gaps (tracked, not silently accepted)

1. **History stores hold plaintext PII** — the Mongo `*_history` models and the paper_trail `versions`
   table keep plaintext copies of the encrypted fields. This is the largest residual SC-28 gap and has
   its own entry: **[POAM-SC28-HIST](history-store-sc28-poam.md)** (accepted for the synthetic demo
   box; hard gate before real data).

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
`rake encryption:backfill TIER=N CONFIRM=1` → `rake encryption:verify TIER=N`. Tier 4's backfill is a
name-**search** blocker (not a login blocker) for un-backfilled rows; Tier 3's email backfill is a
login blocker and must precede login.
