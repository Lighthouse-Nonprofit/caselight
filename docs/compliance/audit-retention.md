# Audit Record Retention Policy — AccessLog (CaseLight)

Status: active. Owner: CaseLight security engineering. Review cadence: annual,
or on any change to the audit pipeline.

Control mapping:
- **AU-11 (Audit Record Retention)** — primary control this policy satisfies.
- **AU-9 (Protection of Audit Information)** — append-only / WORM immutability.
- **AU-6 (Audit Review, Analysis, and Reporting)** — review cadence below.
- **AU-2 / AU-3 / AU-12** — what is captured and that it is generated (see the
  `AccessLog` model and the `AccessAudit` concern; out of scope for this doc).
- **SOC 2 CC7.2** — ongoing monitoring of security events (read access, login
  failure, lockout, access-denied) is retained long enough to support detection.
- **SOC 2 CC7.3** — evaluation of events draws on the retained online window.

## 1. What this policy governs

The `AccessLog` collection (Mongoid; MongoDB 6.0) holds the **access (read) log
and security-event log**: `read`, `login_failure`, `account_locked`,
`access_denied`. It is distinct from:
- **paper_trail `versions`** (PostgreSQL, per-tenant via Apartment) — the *change*
  audit (who changed what). Retained with the relational data; not governed here.
- **lograge JSON request logs** — transport/request logs shipped off-box; their
  retention is an infrastructure concern (log pipeline), not this policy.

`AccessLog` is **append-only at the application layer**: `before_update` and
`before_destroy` raise, so no request-path code can mutate or delete an audit
row. The retention purge defined in section 4 is the **one sanctioned deletion
path** and it bypasses those callbacks deliberately (`delete_all`).

## 2. Tenancy of the audit store (AU-9)

PostgreSQL is isolated **schema-per-tenant** by Apartment. MongoDB is a **single
shared database**; `AccessLog` is tenant-isolated only by an explicit `tenant`
field plus a `default_scope { where(tenant: Organization.current...) }`. Every
normal query is therefore scoped to the current tenant and cannot read another
tenant's audit rows. The retention purge is the deliberate exception: it must
span all tenants and so runs **`unscoped`** (section 4.3).

## 3. Retention schedule (AU-11)

| Tier | Location | Minimum retention | Mutability |
|---|---|---|---|
| Online | MongoDB `AccessLog` | **>= 90 days** | App append-only |
| Archive | WORM object store (S3 Object Lock, compliance mode) or CloudWatch Logs with a retention lock | **>= 1 year** (target: per the system SSP / data-handling baseline) | Infra-enforced immutable |

- **Online window (>= 90 days):** rows stay queryable in Mongo for at least 90
  days so AU-6 review and CC7.2/CC7.3 detection work against live data. 90 days
  is the floor; operators may set a longer `DAYS` value.
- **Archive (>= 1 year):** rows are exported to **WORM storage** before they
  leave the online window. WORM enforcement (Object Lock retention period /
  legal hold, or a CloudWatch Logs retention policy) is the **infrastructure
  hand-off** — the application cannot and does not enforce 1-year immutability
  itself. The app layer guarantees immutability *while online* (append-only
  model); the infra layer guarantees it *in archive*.

## 4. The sanctioned purge path

### 4.1 Mechanism
`rake audit:purge` (`lib/tasks/audit.rake`). It selects rows older than `DAYS`
(default **90**) via `AccessLog.older_than(DAYS)` and deletes them with
`delete_all` — the callback-skipping path, which is *intended*: the append-only
`before_destroy` guard protects the request path, not this operator task.

### 4.2 Archive-before-delete guard (AU-9 / AU-11)
Deletion is destructive and irreversible. The task therefore:
- **Defaults to DRY-RUN.** It only reports the cutoff and the count to be
  purged. Nothing is deleted unless the operator passes `CONFIRM=1`.
- **Must not delete before archive is confirmed.** Purging online rows is only
  authorized once those rows have been written to WORM archive (section 3) and
  the archive write is verified. The dry-run count is the reconciliation handle:
  the operator confirms the same window has been archived before re-running with
  `CONFIRM=1`. Until the archive export is wired into this task (infra
  hand-off), CONFIRM is a manual gate, not an automated one. A code-enforced
  verified-archive precondition is tracked as a POA&M item.

### 4.3 Cross-tenant semantics (the crux)
`AccessLog` carries a tenant-bound `default_scope`. In a rake/console context no
tenant is switched, so `Organization.current` is `nil` and the default scope
resolves to `where(tenant: nil)` — which would match **nothing**. The purge task
therefore runs against **`AccessLog.unscoped`** so it spans **every tenant** in
the shared Mongo database in a single pass, regardless of `Organization.current`.
This is the deliberate cross-tenant exception noted in section 2; it is safe
because retention is a uniform, org-agnostic policy (the 90-day floor applies
identically to all tenants) and the task only ever *deletes by age*, never reads
or moves content between tenants. The task logs a per-tenant breakdown of what
it purged so the cross-tenant action is auditable.

### 4.4 What is never purged early
The purge selects strictly by `created_at` age. It never targets a tenant, a
user, a resource, or an event type — there is no path to selectively erase a
subset of one tenant's trail. This preserves the integrity guarantee that the
only way a row leaves the online store is by aging out uniformly.

## 5. Review (AU-6) and monitoring (CC7.2/CC7.3)

- Security-event rows (`login_failure`, `account_locked`, `access_denied`) are
  reviewed at least **weekly**; spikes are escalated per the incident-response
  process. The >= 90-day online window guarantees review always has data.
- Read-access rows (`read`) support after-the-fact investigation of who viewed
  which client/case records; retained for the same online window and archived.
- Archived (>= 1 year) records support longer-horizon investigation and any
  contractual / regulatory retention obligation for the resettlement program.

## 6. Operational notes
- Run via Sidekiq-cron or an OS cron once daily, **dry-run first**, reconcile the
  count against the archive export, then run with `CONFIRM=1`.
- The task is idempotent: re-running with the same `DAYS` after a successful
  purge reports/deletes only newly-aged rows.
- Never lower `DAYS` below 90 without a documented exception — 90 days is the
  AU-11 online floor for this system.
