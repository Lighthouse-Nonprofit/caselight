# Audit Logging Policy — CaseLight

_NIST 800-53: AU-2, AU-3, AU-6, AU-9, AU-12. SOC 2: CC7.2, CC7.3. Owner: the operating nonprofit.
Review: annually or on any change to the audit pipeline. Retention detail: `audit-retention.md`._

## Purpose
Record who did what, when — across access, security events, and record changes — in trails that are
attributable, tenant-isolated, tamper-resistant, and free of a second copy of the sensitive data they
protect.

## Policy

1. **Three complementary trails** (do not conflate them — full narrative in `audit-logging.md`):
   - **Access / security audit** — `AccessLog` (MongoDB, append-only, tenant-scoped): sensitive-record
     **reads**, `login_failure`, `account_locked`, `access_denied`, `record_destroyed`,
     `account_disabled`, `record_exported`, `enforcement_flag_changed`.
   - **Change audit** — paper_trail `versions` (PostgreSQL, per-tenant): create/update/destroy of
     records — who/when/event. PII values are **redacted at write** (encrypted fields are skipped), so
     the change log is not a plaintext PII shadow.
   - **Request log** — lograge JSON, one line per request, values-free tags only.
2. **Data minimization (AU-3).** Audit rows store **identifiers only** (resource type + id) plus the
   one allowed human handle (`user_email`, denormalized so the trail outlives the account). Never
   record contents (names / DOB / notes) — a hard review rule; `metadata` carries only non-sensitive
   context.
3. **Tamper resistance (AU-9).** `AccessLog` is append-only at the app layer (update/destroy raise);
   the only sanctioned deletion is the retention purge. True WORM immutability and protection from a
   privileged operator are inherited infra controls (immutable object store, DB ACLs, at-rest
   encryption, backups).
4. **Review (AU-6, CC7.2/CC7.3).** Security-event rows are reviewed at least **weekly** (spikes
   escalated per the incident-response policy); read-access rows support after-the-fact "who viewed
   this client" investigation. Reviews run against the ≥90-day online window (`audit-retention.md`).
5. **Retention (AU-11).** AccessLog: ≥90 days online / ≥1 year WORM archive (`audit:purge`, 90-day
   code floor). Change/history stores: `retention:purge_*` (365-day floor; 3-year windows ratified
   2026-07-26). All purges dry-run by default, require `CONFIRM=1`, and — since POAM-015 closed
   (2026-07-26) — **refuse in code without a verified archive** (archive → verify → purge, weekly
   on the host crontab; a failed verify makes the purge a refusal). Policy detail:
   `data-retention.md`, `audit-retention.md` §4.2.
6. **Resilience.** Auditing must never break the request it audits — every writer is rescue-wrapped
   and downgrades a failure to a logged error.

## Enforcement anchors
`app/models/access_log.rb`, `app/controllers/concerns/access_audit.rb`,
`config/initializers/{warden_audit,lograge,paper_trail,filter_parameter_logging}.rb`,
`lib/tasks/{audit,retention}.rake`. See `audit-logging.md` for the per-control implemented/inherited
split and `ssp.md` §3 (AU rows).
