<p align="center">
  <picture>
    <source media="(prefers-color-scheme: dark)" srcset="../app/assets/images/brand/caselight-logo-ondark.png">
    <img alt="CaseLight" src="../app/assets/images/brand/caselight-logo.png" width="360">
  </picture>
</p>

# CaseLight — User Guide

CaseLight is a case-management system for refugee resettlement and other frontline nonprofits.
It tracks the people you serve, the households they belong to, the programs they move through,
and the assessments and notes that record how the work is going — with security controls usually
reserved for far more expensive software.

This guide walks through the app the way staff actually use it, role by role and screen by screen.

> **All screenshots in this guide show synthetic demo data** — fictional names, addresses, and
> records generated for demonstration. No real client information appears anywhere.

## Contents

1. [Signing in](#1-signing-in)
2. [Roles at a glance](#2-roles-at-a-glance)
3. [The dashboard](#3-the-dashboard)
4. [Individuals & households](#4-individuals--households)
5. [The individual record](#5-the-individual-record)
6. [Programs & enrollments](#6-programs--enrollments)
7. [Case notes](#7-case-notes)
8. [Assessments & domains](#8-assessments--domains)
9. [The calendar](#9-the-calendar)
10. [Custom forms — the form builder](#10-custom-forms--the-form-builder-administrators)
11. [Security & administration](#11-security--administration-administrators)
12. [Data protection & privacy](#12-data-protection--privacy)

---

## 1. Signing in

<p align="center"><img src="screenshots/login.jpg" alt="CaseLight sign-in screen" width="640"></p>

Each staff member has their own account — one person per login, so the audit history is meaningful.
Sign in with your email and password. CaseLight supports two additional protections you can enable:

- **Multi-factor authentication (MFA)** — a time-based one-time code from an authenticator app, with
  one-time recovery codes.
- **Passkeys** — phishing-resistant WebAuthn sign-in (Face ID / Touch ID / a security key), via the
  **"Sign in with a passkey"** button.

Administrators can require MFA for privileged roles. Repeated failed sign-ins lock an account
temporarily; it unlocks automatically after a set interval.

## 2. Roles at a glance

CaseLight shows the **same records** to everyone who's authorized, but presents them in the way each
role works — and limits what lower-privilege roles can see.

| Role | Sees | Individuals view |
|---|---|---|
| **Administrator** | Everything; manages users, forms, programs, and security | Dense table |
| **Strategic overviewer** | Read-only overview across the organization (standard-sensitivity data) | Dense table |
| **Manager** | The caseloads of the case workers they manage | Cards |
| **Case worker** | Only the clients assigned to them | Cards |
| **Specialized managers** (EC / FC / KC / Able) | Program-specific management | Cards |

Sensitive fields are additionally gated by **field-level sensitivity** (see
[§12](#12-data-protection--privacy)) — a role that can open a record still won't see fields marked
above its clearance.

## 3. The dashboard

<p align="center"><img src="screenshots/dashboard.jpg" alt="The resettlement dashboard" width="900"></p>

The dashboard is the landing page after sign-in. It summarizes the organization at a glance:

- **Headline counts** — households, individuals, active program enrollments, and programs offered.
- **Active enrollments by program** — how many people are currently in Housing, Employment,
  Immigration/Legal, Education, Benefits, and so on.
- **Households** — every household with its member count, each a link into the record.
- **Recent program activity** — the latest dated updates across the caseload.

## 4. Individuals & households

Every person in CaseLight is an **individual**, and every individual belongs to a **household**.
Households are listed under **Households**; individuals under **Individuals**.

<p align="center"><img src="screenshots/families.jpg" alt="The households list" width="900"></p>

Depending on your role, the **Individuals** list appears one of two ways:

**Administrators & strategic overviewers** get a dense, sortable table — name, case manager,
gender/age, status, and program-stream tags — with export and advanced search:

<p align="center"><img src="screenshots/clients-grid.jpg" alt="Individuals as a sortable table" width="900"></p>

**Managers & case workers** get a card per person, scoped to the caseload they carry:

<p align="center"><img src="screenshots/clients-cards.jpg" alt="Individuals as cards" width="900"></p>

From either view you can **add a new individual**, run an **advanced search**, view **all active
tasks**, and **export** program data.

## 5. The individual record

<p align="center"><img src="screenshots/client-detail.jpg" alt="An individual's record" width="900"></p>

An individual's page brings the whole picture together:

- **About the individual** — code, date of birth, age, address, country of origin, school
  information, referral source, **assigned case managers**, and accept/reject status.
- **Household link** — one click to the household the person belongs to.
- **Resettlement case** — intake date, household, case managers, and status.
- **Action bar** — open the resettlement case, view **Tasks**, **Assessments**, **Case Notes**,
  add **Additional Forms**, and manage **Program Streams**.

## 6. Programs & enrollments

Programs are modeled as **program streams** — enrollable programs, each with its own custom form
and recurring, date-stamped check-ins ("trackings"). Administrators define the streams the
organization actually runs.

<p align="center"><img src="screenshots/programs.jpg" alt="Program streams" width="900"></p>

Enroll an individual in one or more streams, then log dated trackings against each enrollment as the
work progresses. The history of the case is captured as it happens.

<p align="center"><img src="screenshots/client-programs.jpg" alt="A person's enrolled program streams" width="900"></p>

## 7. Case notes

<p align="center"><img src="screenshots/case-notes.jpg" alt="Case notes for an individual" width="900"></p>

Case notes are the running narrative of the work with a person — dated entries attached to the
individual, visible to the staff authorized to see that record.

## 8. Assessments & domains

CaseLight includes a structured **assessment** engine: periodic, scored needs assessments across
**life domains** (for example Health, Mental Health, Immigration Status, Personal Safety, Education).
Administrators configure the domains and their scoring under **Manage → Domains**.

<p align="center"><img src="screenshots/domains.jpg" alt="Assessment domains configuration" width="900"></p>

Each domain can be marked with a **sensitivity level**, so the most protected domains (for example
Mental Health or Immigration Status) are only visible to appropriately cleared roles.

## 9. The calendar

<p align="center"><img src="screenshots/calendar.jpg" alt="The shared monthly calendar" width="900"></p>

Appointments, recertification dates, and program milestones appear on a shared calendar with
month / week / day views. Each user sees the events for the caseloads they're allowed to see.
Clicking a day lets you schedule a task against a program, person, and domain.

## 10. Custom forms — the form builder (administrators)

CaseLight is configurable **without code**. Rather than editing the data model, administrators add
**custom forms** (attachable to individuals, households, users, or partners) using a drag-and-drop
builder under **Manage → Form Builder**.

<p align="center"><img src="screenshots/form-builder.jpg" alt="The form builder with a sensitivity selector" width="900"></p>

Choose the record **type**, an optional **frequency**, and — importantly — the form's **sensitivity**:

- **Standard** — any authorized reader of the record.
- **Restricted** — caseload- or role-scoped readers only.
- **Emergency only** — hidden unless a **break-glass** grant is active (see below).

Then drag fields (text, number, date, select, checkbox/radio groups, file upload, text area) into the
form. When the organization needs to capture something new, an administrator designs it here — no
developer and no database migration required.

## 11. Security & administration (administrators)

CaseLight surfaces its security posture to the administrators who own it, rather than hiding it in a
vendor's data center.

### Access Review

<p align="center"><img src="screenshots/access-review.jpg" alt="The Access Review report" width="900"></p>

**Access Review** (under the main menu) is a periodic account-recertification report: every account
with its role, last sign-in, MFA and passkey status, and whether it's locked or disabled. It also
flags **disabled staff who still hold caseloads** and summarizes the least-privilege and
authorization "shadow" windows. Export it to CSV for your records.

### Security Enforcement

<p align="center"><img src="screenshots/enforcement.jpg" alt="The Security Enforcement panel" width="720"></p>

The **Security Enforcement** panel lets an administrator turn live security controls on or off **for
their organization**, each mapped to a NIST 800-53 control:

- **Global authorization enforcement** (AC-3) — require every action to authorize explicitly.
- **Least-privilege narrowing** (AC-6) — scope reads to need-to-know.
- **Tenant-boundary tripwire** (SC-7) — refuse any cross-tenant request.
- **Require MFA** (IA-2), **idle session timeout** (AC-12), **account lockout threshold** (AC-7),
  **password expiry** (IA-5), and **inactive-account auto-disable** (AC-2(3)).

Each control shows a **shadow window** first — what the stricter rule *would* have denied — so you can
review the impact before enabling it.

### Break-glass emergency access

When a genuine life-safety need requires seeing an **emergency-only** field, an eligible worker can
**self-elevate for one hour** — with a **mandatory reason** and the audit record written *first*.
Access is scoped to the specific record, expires automatically, and is fully logged.

## 12. Data protection & privacy

CaseLight is hardened at the application layer toward **NIST 800-53 Moderate** and **SOC 2**
(Security, Confidentiality, Privacy), and aligns with the **HIPAA Security Rule**. Highlights:

- **Field-level sensitivity** — Standard / Restricted / Emergency-only on forms and assessment
  domains; records mask what a role isn't cleared to see.
- **Encryption at rest** — sensitive PII is encrypted in the database across multiple tiers.
- **Append-only audit trail** — record reads and changes are logged to a separate, tenant-isolated
  store, with change history and retention.
- **Tenant isolation** — each organization is its own subdomain and database schema.
- **Data lifecycle** — retention/deletion routines, guarded and audited deletion, and a
  **subject-access export** for producing everything held about an individual.

The full compliance package lives in [`docs/compliance/`](compliance/) — the System Security Plan,
SOC 2 control matrix, policies, and a reproducible evidence bundle. Data-handling posture and the
production gate for **real** client data are in [`../SECURITY.md`](../SECURITY.md).

> **Pilot data is synthetic only.** Moving to real client records is a deliberate, separate decision
> that requires meeting the production gate documented in `SECURITY.md`.
