# Audit & Access Logging — Control Narrative

_FedRAMP Moderate (AU family) + SOC 2 (CC7.2 / CC7.3). Last updated: Phase 3._

This document maps CaseLight's audit-logging implementation to the relevant
controls. It is the companion to [`audit-retention.md`](audit-retention.md)
(AU-11 detail) and sits alongside the existing POA&M material in
`docs/compliance/`.

Scope note on the shared-responsibility line: CaseLight is the **application**
layer. It generates audit records and isolates them per tenant. The **immutable
storage / WORM, time-sync, and operator-access-control** properties of those
records are **inherited** from the deployment infrastructure (the EC2 box, its
MongoDB deployment, OS logging, and the reverse proxy). Each control below names
which side owns which property. "Implemented" = in this repo; "Inherited" =
provided/operated by infra and out of application scope.

## Architecture summary

CaseLight is multi-tenant by subdomain. `ros-apartment` isolates the
**PostgreSQL** relational data by **schema-per-tenant**. **MongoDB is a single
shared database**, so Mongo-backed models are tenant-isolated only by an
explicit `tenant` field plus a `default_scope` convention (the long-standing
`ClientHistory` pattern). The Phase 3 audit store, `AccessLog`, follows that
same pattern — this is the crux of the AU-9 isolation requirement, because a
naive shared-Mongo model would leak audit rows across tenants.

Two distinct audit trails exist; do not conflate them:

| Trail | Store | What it records | Control role |
|---|---|---|---|
| **Change audit** | `paper_trail` ~> 15, Postgres `versions` table (per-tenant via Apartment) | who **changed** what (create/update/destroy of records) | pre-existing; not Phase 3 |
| **Access / security audit** | `AccessLog` (Mongoid, shared Mongo, tenant-scoped) | who **read** sensitive records + authentication/authorization security events | **Phase 3 (this document)** |
| **Request log** | `lograge` ~> 0.14, JSON to Rails log / stdout | one structured line per HTTP request | AU-3 content (pre-existing increment) |

---

## AU-2 — Auditable Events

**Requirement:** define and capture the security-relevant events the system must
audit.

**Implemented by CaseLight.** The audited event set is:

- **Record reads** of sensitive resources — `event_type: "read"`. Captured by
  the `AccessAudit` concern (`app/controllers/concerns/access_audit.rb`) on
  successful `show` and `index` of the four sensitive controllers
  (`ClientsController`, `ProgressNotesController`, `AssessmentsController`,
  `CaseNotesController`). Reads matter here because the change audit
  (`paper_trail`) only sees writes; a read of a refugee client's file is itself
  the sensitive event.
- **Failed logins** — `event_type: "login_failure"`. Captured by the Warden
  `before_failure` hook (`config/initializers/warden_audit.rb`).
- **Account lockouts** — `event_type: "account_locked"`. Emitted from the same
  Warden hook when the attempted email maps to a now-`access_locked?` user.
- **Authorization denials** — `event_type: "access_denied"`. Emitted from the
  `CanCan::AccessDenied` and `Pundit::NotAuthorizedError` `rescue_from` blocks
  in `ApplicationController`.

All four event types are written to the **one** `AccessLog` model
(`app/models/access_log.rb`), keeping the event taxonomy in a single place.
**Read-access** logging can be toggled via `config.x.access_logging_enabled`
(defaults **true**), following the existing `config/initializers/two_factor.rb`
flag pattern; the default-on posture is the compliant one, and the concern fails
safe (a missing flag keeps logging ON). **Security events** (login_failure /
account_locked / access_denied) are **always recorded regardless of this flag** —
the toggle governs only the `read` event type.

**Inherited from infra:** OS / container / reverse-proxy events (SSH sessions,
sudo, network ACL hits) are audited at the host layer, not by CaseLight.

---

## AU-3 — Content of Audit Records

**Requirement:** each audit record contains enough context — what, when, where,
who, outcome.

**Implemented by CaseLight.** Two complementary record shapes:

1. **Structured request logs (lograge).** `config/initializers/lograge.rb`
   emits one JSON line per request with `custom_options`:
   `{ time, request_id, user_id, tenant, remote_ip }`. These tags are populated
   by `ApplicationController#append_info_to_payload`
   (`request_id` / `user_id` / `tenant = Apartment::Tenant.current rescue nil` /
   `remote_ip`). Disabled in `test`. This satisfies the AU-3 content increment
   for the request stream and is **not** modified by Phase 3.

2. **`AccessLog` records.** Each row carries:
   `tenant`, `event_type`, `user_id`, `user_email`, `resource_type`,
   `resource_id`, `controller`, `action`, `http_method`, `path`, `remote_ip`,
   `request_id`, `metadata`, and a `created_at` timestamp. `request_id`
   correlates an `AccessLog` row back to its lograge request line. Each write
   also emits a content-free `"access_log"`-tagged JSON line via
   `Rails.logger.info` so the event survives a Mongo outage (lograge replaces
   only the per-request log line; explicit `Rails.logger` calls pass through).

**Data-minimization (privacy-relevant AU-3 design).** `AccessLog` stores **only
identifiers** — resource type and id — never record **contents** (no names,
DOB, notes). `user_email` is the single allowed human identifier and is
**denormalized** deliberately so the actor handle survives user deletion (the
trail must outlive the account). `metadata` carries only non-sensitive context
(attempted_email, factor, reason, source); callers must never stuff record
attributes into it. This keeps the audit store from becoming a second, weaker
copy of the sensitive client data it is meant to protect.

**Inherited from infra:** authoritative, trusted **time** (NTP / time-sync,
related to AU-8) is provided by the host; CaseLight records `created_at` from
the app clock, which depends on host time being correct.

---

## AU-6 — Audit Review, Analysis & Reporting

**Requirement:** the audit trail can be reviewed and analyzed.

**Implemented by CaseLight.** `AccessLog` is a queryable Mongoid model with
indexes purpose-built for review:

- `{ tenant: 1, created_at: -1 }` — chronological review within a tenant.
- `{ tenant: 1, user_id: 1, created_at: -1 }` — "what did this actor access?"
- `{ tenant: 1, resource_type: 1, resource_id: 1 }` — "who accessed this
  client?"

Because the `default_scope` pins every query to the current tenant, a reviewer
operating inside a tenant context sees only that tenant's trail by
construction — review cannot accidentally cross tenants. Reviewers query via the
Rails console or any read tooling against these indexes; the structured lograge
stream is additionally consumable by host/SIEM log tooling.

**Inherited from infra:** alerting, dashboards, long-term aggregation/SIEM, and
operator review **workflow/cadence** are infra/operational responsibilities.
CaseLight makes the data reviewable; the infra/SOC makes review happen on a
schedule.

---

## AU-9 — Protection of Audit Information

**Requirement:** protect audit information from unauthorized access,
modification, and deletion.

**Implemented by CaseLight (two layers):**

1. **Tenant isolation.** `AccessLog` carries an explicit `tenant` field
   (default `-> { Organization.current.try(:short_name) }`) and a
   `default_scope { where(tenant: Organization.current.try(:short_name)) }`,
   mirroring `ClientHistory`. Since Mongo is a **single shared database**, this
   field+scope is what prevents one org's audit trail from leaking into
   another's. `Organization.current` may be nil outside a tenant
   (console/jobs), so both the default lambda and the scope use `try` and never
   raise — a missing tenant context degrades gracefully instead of crashing or
   mis-tagging.
2. **Append-only at the application layer.** `AccessLog` includes
   `Mongoid::Timestamps::Created` only (a `created_at`, no `updated_at` — there
   is no legitimate update). `before_update` and `before_destroy` **raise**, so
   no normal application code path can mutate or delete an audit row. The single
   sanctioned deletion path is the retention purge (see AU-11), which uses
   `delete_all` to bypass the destroy callback by design and is documented as
   the one allowed exception.

**Resilience property (so auditing never harms availability):** all `AccessLog`
writes are wrapped so a logging failure is **rescued and sent to
`Rails.logger.error`**, never raised into the request. Auditing is a safety
control, not a denial-of-service vector — a Mongo hiccup must not 500 a
caseworker's page load.

**Inherited from infra (the WORM hand-off):** true write-once-read-many
immutability and protection of the store from a privileged operator are **infra
responsibilities** — application-level `before_destroy` raises stop the *app*,
not a DBA with a Mongo shell. Infra owns: MongoDB access control (least-
privilege DB users; the app's runtime user ideally lacks ad-hoc delete outside
the purge job), at-rest encryption, backups, and any WORM/object-lock storage
tier. The application guarantees "the code won't tamper"; infra guarantees "no
one else can either."

---

## AU-11 — Audit Record Retention

**Requirement:** retain audit records for the defined period, then dispose.

**Implemented by CaseLight.** The retention period and the purge mechanism are
documented in [`audit-retention.md`](audit-retention.md). The purge
(`lib/tasks/audit.rake`) is the **only** sanctioned deletion path for
`AccessLog`; it uses `delete_all` (skipping the append-only `before_destroy`
guard intentionally and explicitly), defaults to DRY-RUN, and deletes only when
`CONFIRM=1`. It runs `unscoped` so a single pass spans every tenant in the
shared Mongo DB (the tenant-bound `default_scope` resolves to nothing in a rake
context). Records younger than the retention boundary are never purged.

**Inherited from infra:** backup retention/rotation and any cold-storage tier
beyond the live database are infra-owned and must be configured to at least the
retention period in `audit-retention.md`. The code-enforced verified-archive
precondition before delete is tracked as a POA&M item.

---

## AU-12 — Audit Generation

**Requirement:** the system generates audit records for the AU-2 events at the
correct points.

**Implemented by CaseLight.** Three generation seams, each chosen so the event
is caught where it actually occurs:

- **`AccessAudit` concern** (`app/controllers/concerns/access_audit.rb`) —
  `after_action` on the four sensitive controllers. Records a `read` only when
  `current_user` is present **and** the response is successful (2xx), deriving
  `resource_type` from `controller_name.classify` and `resource_id` from
  `params[:id]` (it does **not** depend on a per-controller ivar name). It is
  wired by `include AccessAudit` in those four controllers and is deliberately
  **not** included in `AdminController` — that would log every admin page rather
  than scoping to sensitive-resource reads.
- **Warden `before_failure` hook**
  (`config/initializers/warden_audit.rb`) — the correct seam for failed
  logins, because a bad password is thrown to Warden / `Devise::FailureApp` and
  never reaches `SessionsController#create`. The hook builds an
  `ActionDispatch::Request` from `env` for ip/path/request_id and reads the
  attempted email from the Devise `:user` params; it also emits
  `account_locked` when that email is now `access_locked?`. It records a
  `metadata["factor"]` discriminator (`password` vs `second_factor`) so a failed
  OTP in the two-step MFA flow is distinguishable from a password failure.
  Apartment middleware runs **before** Warden, so `Organization.current` is set
  and the tenant default resolves correctly inside the hook. The two-step MFA
  `SessionsController` is **not** modified.
- **`rescue_from` blocks** in `ApplicationController` — an `access_denied`
  `AccessLog` write plus a structured `Rails.logger` line inside both the
  `CanCan::AccessDenied` and `Pundit::NotAuthorizedError` rescues, before the
  existing redirect to `root_url`.

**Inherited from infra:** generation of host/network/proxy audit events.

---

## SOC 2 CC7.2 — Detection & Monitoring of Anomalies

**Implemented by CaseLight.** `login_failure`, `account_locked`, and
`access_denied` events give the monitoring layer the security-event signal it
needs to detect anomalous behavior (credential stuffing, lockout storms,
authorization probing). These are first-class `AccessLog` rows, queryable by the
AU-6 indexes and also emitted to the structured Rails log for host/SIEM
consumption. The `metadata["factor"]` discriminator lets a dashboard separate
password brute-force from second-factor noise.

**Inherited from infra:** the actual monitoring/alerting pipeline, thresholds,
and on-call response that turn these signals into detections.

---

## SOC 2 CC7.3 — Evaluation & Response to Security Events

**Implemented by CaseLight.** The `AccessLog` trail is the evidentiary basis for
evaluating a security event: the `read` trail (who accessed which client, when,
from what IP, correlatable to the lograge request line via `request_id`) plus
the security-event rows support incident reconstruction and impact analysis. The
append-only + tenant-isolation properties (AU-9) make that evidence trustworthy
for evaluation.

**Inherited from infra:** the incident-response **process** — triage,
containment, and remediation — is operational and lives outside the application.

---

## Control responsibility summary

| Control | CaseLight implements | Inherited from infra |
|---|---|---|
| AU-2 | Event taxonomy: read / login_failure / account_locked / access_denied (`AccessLog`, `AccessAudit`, Warden hook, rescues) | Host/network event auditing |
| AU-3 | lograge JSON tags + full `AccessLog` field set; id-only data minimization | Trusted time (NTP / AU-8) |
| AU-6 | Queryable, tenant-scoped `AccessLog` with review indexes | SIEM/alerting, review cadence |
| AU-9 | Tenant `default_scope`; append-only `before_update`/`before_destroy` raise; rescue-don't-raise writes | WORM/object-lock, DB ACLs, at-rest encryption, backups |
| AU-11 | Sanctioned `delete_all` purge per `audit-retention.md` | Backup/cold-storage retention; verified-archive precondition (POA&M) |
| AU-12 | `AccessAudit` after_action + Warden `before_failure` + `rescue_from` writes | Host/proxy audit generation |
| CC7.2 | Security-event rows as anomaly signal | Monitoring/alerting pipeline |
| CC7.3 | `AccessLog` as evaluation evidence | Incident-response process |
