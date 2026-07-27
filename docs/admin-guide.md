<!-- Source for docs/pdf/CaseLight-Administrator-Guide.pdf — build with docs/build-pdfs.js.
     (Reconstructed 2026-07-13: the PDF was originally committed without its markdown source.) -->

# CaseLight — Administrator Guide

**Configuring & securing CaseLight** — set up users, tailor the system to your programs
without code, and operate its security controls: everything under **Manage** and the admin
surfaces.

> **All screenshots in this guide show synthetic demo data** — fictional names, addresses,
> and records.

## 1 · Users & access

Under **Users**, add a staff account for each person and assign a role — the role decides
what they can see and do (see the User Guide's role table). Beyond add/edit/export:

- **Manager assignment** — each case worker's record names their manager; that hierarchy is
  what scopes a manager's view to their team's caseloads. Keep it current when teams change.
- **Disable, don't delete** — when staff leave, disable the account. A disabled account cannot
  sign in, but every note, task, and change it made stays attributed. The Access Review report
  flags disabled staff who still hold caseloads so those can be reassigned.
- **Google Calendar sync** — a per-user opt-in on the user record; off by default. The internal
  calendar works either way.
- **User custom fields** — users can carry custom forms too (certifications, training records),
  designed in the same form builder.

<p align="center"><img src="screenshots/manage-users.jpg" alt="Users" width="860"></p>
<p align="center"><em>Users — one account per staff member.</em></p>

### Access Review — periodic recertification

The **Access Review** report (AC-2) lists every account with its role, last sign-in, MFA and
passkey status, and whether it's locked or disabled. It flags disabled staff who still hold
caseloads, and summarizes the least-privilege and authorization shadow windows. Export to
CSV for your records.

<p align="center"><img src="screenshots/access-review.jpg" alt="Access Review" width="900"></p>
<p align="center"><em>Access Review — recertify accounts and catch orphaned caseloads.</em></p>

## 2 · Configure without code: the form builder

Rather than editing the data model, add **custom forms** (attachable to individuals,
households, users, or partners) with a drag-and-drop builder under **Manage → Form
Builder**.

<p align="center"><img src="screenshots/form-builder.jpg" alt="The form builder" width="900"></p>
<p align="center"><em>The form builder — choose type, frequency, and the form's sensitivity, then drag in fields.</em></p>

Every form carries a **sensitivity**, set at design time:

- **Standard** — any authorized reader of the record.
- **Restricted** — caseload- or role-scoped readers only.
- **Emergency only** — hidden unless a break-glass grant is active (see §6).

> Because sensitivity is chosen when the form is designed, a brand-new form can never
> accidentally expose data — it inherits an explicit classification from the start.

**Designing good forms.** Two rules of thumb carry most of the weight:

- **Tracking form or custom form?** Data that belongs to a *program* (a recurring check-in that
  only makes sense while enrolled) is a tracking on that program stream (§3). Data that belongs
  to the *person or household* regardless of program is a custom form. Ask: "would we still
  record this if they left the program?"
- **Pick widgets for the analysis, not just the entry.** Selects, radio groups, and checkboxes
  produce countable, filterable data (checkboxes = multi-select, radios = one answer); free-text
  areas produce narrative that Advanced Search can't aggregate. Don't re-collect identifying
  details the record already holds, and keep forms short — every field is work for frontline
  staff on every entry.

Individual forms appear on the person's **Forms** tab; household forms on the household's.

## 3 · Program streams

Define the programs your organization actually runs under **Manage → Programs**.
Each stream is enrollable, has its own custom form, and supports recurring, date-stamped
trackings.

Before building anything, sketch your organization's program flow on paper — where people
enter, the decision points, where they exit. It doesn't have to be perfect, just good enough
to name the streams. Each stream then gets: program details, optional **enrollment rules**
(conditions a person must meet, with a preview of who currently qualifies), an **enrollment
form**, one or more **tracking forms**, and an **exit form**. Editing a stream that already
has enrollments shows a warning first — form changes affect everyone enrolled, so coordinate
with whoever owns that program's reporting.

<p align="center"><img src="screenshots/programs.jpg" alt="Program streams" width="900"></p>
<p align="center"><em>Program streams — the enrollable programs behind every case.</em></p>

## 4 · Assessment domains & groups

The assessment engine scores needs across **life domains**, organized into **domain
groups**. Configure both under Manage, and set each domain's **sensitivity** so the most
protected domains stay restricted.

<p align="center"><img src="screenshots/manage-domain-groups.jpg" alt="Domain groups" width="860"></p>
<p align="center"><em>Domain groups.</em></p>

<p align="center"><img src="screenshots/domains.jpg" alt="Domains with sensitivity" width="900"></p>
<p align="center"><em>Domains (with sensitivity).</em></p>

## 5 · Reference data

The lists that populate dropdowns and organize your work — all editable under **Manage**.
Keep them tidy and every record downstream stays consistent.

<p align="center">
  <img src="screenshots/manage-agencies.jpg" width="49%" alt="Agencies">
  <img src="screenshots/manage-departments.jpg" width="49%" alt="Departments">
</p>
<p align="center"><em>Agencies — partner and referring organizations. · Departments — internal structure for staff.</em></p>

<p align="center">
  <img src="screenshots/manage-referral-sources.jpg" width="49%" alt="Referral sources">
  <img src="screenshots/manage-donors.jpg" width="49%" alt="Donors">
</p>
<p align="center"><em>Referral sources — how clients reach you. · Donors — funding sources for reporting.</em></p>

<p align="center">
  <img src="screenshots/manage-quantitative-types.jpg" width="49%" alt="Quantitative types">
  <img src="screenshots/manage-progress-note-types.jpg" width="49%" alt="Types of Note">
</p>
<p align="center"><em>Quantitative types — countable service categories. · Types of Note — categories for progress notes.</em></p>

### Partners

External **Partners** (agencies you coordinate with) get their own records and custom forms,
tracked separately from the individuals you serve.

<p align="center"><img src="screenshots/partners.jpg" alt="Partners" width="860"></p>
<p align="center"><em>Partners.</em></p>

## 6 · Security enforcement & break-glass

The **Security Enforcement** panel turns live security controls on or off for your
organization, each mapped to a NIST 800-53 control, and each showing a **shadow window** —
what the stricter rule *would have* denied — so you can review impact before enabling.

Since **2026-07-26** the three authorization controls (global authorization, least-privilege
narrowing, and the tenant-boundary tripwire) are **on by default in production** — the flip was
made after the shadow window recorded zero divergences. Your panel settings still override the
default in either direction, and every change is audited. Account-affecting controls (like
requiring MFA) follow the **enforcement-window policy**: they stay off until your staff have had
time to enroll their authentication of choice.

<p align="center"><img src="screenshots/enforcement.jpg" alt="Security Enforcement panel" width="720"></p>
<p align="center"><em>Security Enforcement — per-organization control toggles.</em></p>

| Control | NIST | What it does |
|---|---|---|
| Global authorization | AC-3 | Require every action to authorize explicitly. |
| Least-privilege narrowing | AC-6 | Scope reads to need-to-know. |
| Tenant-boundary tripwire | SC-7 | Refuse any cross-tenant request. |
| MFA & idle timeout | IA-2 · AC-12 | Require MFA; invalidate idle sessions. |
| Lockout & password expiry | AC-7 · IA-5 | Lock after failed sign-ins; rotate passwords. |
| Inactive-account auto-disable | AC-2(3) | Disable dormant accounts automatically. |

### Break-glass emergency access

When a genuine life-safety need requires an emergency-only field, an eligible worker can
self-elevate for **one hour** — with a mandatory reason and the audit record written
*first*. Access is scoped to the specific record, expires automatically, and is fully
logged.

## 7 · Data protection & privacy

CaseLight is hardened at the application layer toward **NIST 800-53 Moderate** and **SOC 2**
(Security, Confidentiality, Privacy), and aligns with the **HIPAA Security Rule**.

- **Field-level sensitivity** — Standard / Restricted / Emergency-only on forms and domains;
  records mask what a role isn't cleared to see.
- **Encryption at rest** — sensitive PII is encrypted in the database across multiple tiers.
- **Append-only audit trail** — reads and changes logged to a separate, tenant-isolated
  store, with change history and retention.
- **Tenant isolation** — each organization is its own subdomain and database schema.
- **Data lifecycle** — retention/deletion routines, guarded and audited deletion, and a
  subject-access export.

### Data-lifecycle operations (command line)

Three operator tasks cover the lifecycle obligations; each is dry-run by default and requires
`CONFIRM=1` (or an explicit tenant/client) to act:

- **Subject-access export** — `rake privacy:subject_access_export TENANT=<t> CLIENT=<id>`
  produces everything held about one person as a reviewable bundle under `tmp/exports/`, and
  writes an audit-log entry recording the export.
- **Retention** — `rake retention:report` shows what is past policy;
  `rake retention:purge_versions` / `retention:purge_client_histories` purge aged change
  history (a `DAYS` floor guards against accidentally aggressive runs).
- **Deletion** — client deletion from the Actions menu is guarded and audited; it removes the
  record and its dependents, while the append-only audit log keeps the fact that a deletion
  happened.

Deploy and box operations (the bootstrap script, encryption backfills, and their invariants)
are documented in [`../OPERATIONS.md`](../OPERATIONS.md).

> The full compliance package — System Security Plan, SOC 2 control matrix, policies, POA&M,
> and a reproducible `rake compliance:evidence` bundle — lives in `docs/compliance/`.
> Data-handling posture and the production gate for real client data are in `SECURITY.md`.
> **Pilot data is synthetic only.**
