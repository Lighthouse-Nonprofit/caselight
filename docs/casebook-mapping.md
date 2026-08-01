# Casebook → CaseLight mapping (One Community Action)

Youth-flavor batch Y5. The importer reads OCA's six Casebook dashboard exports
(xlsx; the raw export table is the **last** sheet of each workbook, below a
title/meta row) and maps them onto the youth-flavor taxonomy seeded by
`youth:seed_*` (Y3). Read this next to `lib/tasks/casebook_import.rake` and
`app/services/casebook/`.

## Ground rules

- **PII**: real exports never leave the operator's machine; the repo carries only
  synthetic fixtures. `casebook:audit` is read-only and prints **aggregates only**
  (counts, blank rates, collision counts — never a name or narrative).
- **Gate**: `casebook:import` is DRY_RUN by default. It persists only when ALL of
  `CONFIRM=1`, `RAILS_ENV=production`, and an explicit `TENANT=` are present —
  the synthetic-only rule for every other box, enforced in code.
- **Blanks stay blank.** The point of the migration is honest reporting; we do not
  invent values Casebook never had. The audit's blank-rate table is the baseline
  OCA improves from.
- **Idempotency**: Casebook GUIDs (`person_id`, `case_id`, `provider_id`) are
  stored in the "Imported from Casebook" custom form on each created record.
  Re-running the import upserts by GUID; `clients.code` stays free.

## Workbooks → extractors

| Workbook | Last sheet (raw table) | Rows | Extractor |
|---|---|---|---|
| People Reports.xlsx | People Data Table | 727 | `Casebook::PeopleSheet` |
| Cases Summary (1).xlsx | Cases Data Table | 1,163 | `Casebook::CasesSheet` |
| Notes Reports.xlsx | Client Notes | 8,045 | `Casebook::NotesSheet` |
| Providers Summary.xlsx | Providers Data Table | 20 | `Casebook::ProvidersSheet` |
| Service Notes Summary.xlsx | Note-level Details | 4,587 | cross-check only |
| Population Served on Cases.xlsx | All Cases and People in Re | 721 | cross-check only |

`Casebook::WorkbookReader` opens a workbook with `Roo::Excelx`, takes the LAST
sheet, skips leading meta rows (rows with ≤3 non-blank cells), treats the first
wide row as the header, and yields one `{header => value}` hash per data row.

## People Data Table → `Client`

| Casebook column | CaseLight | Note |
|---|---|---|
| Person Name | `given_name` / `family_name` | split on last space; the audit lists ambiguous names |
| person_id | Imported-from-Casebook form, `Casebook person_id` | idempotency key |
| Age | Imported-from-Casebook form, `Age at export (2026-07)` | export has **no DOB**; `date_of_birth` stays nil |
| Sex | `gender` | Casebook's list maps onto the SOGI-aware field; unknown → blank |
| Primary Language | quantitative "Preferred Language" | includes Mixteco/Zapoteco/Triqui/Purépecha (Y3) |
| Race | quantitative "Race" (multi) | comma-split |
| Hispanic/Latino | quantitative "Ethnicity" | |
| Poverty Level | quantitative "Poverty Level" | 69% blank in the export — stays blank |
| Education | Imported-from-Casebook form | 85% blank — stays blank |
| Address / City / Zip Code | `current_address` (one composed line) | clients carry a single address text field; County dropped (all Santa Barbara) |
| Birthplace, Employer, Income* etc. | Imported-from-Casebook form | verbatim, only when present |

## Cases Data Table → `ClientEnrollment` (by role)

Join to People **by name** (no person_id in this sheet — the audit counts
collisions first; collided names are listed for manual resolution and skipped by
the import until resolved).

| Person Role | Target |
|---|---|
| Student (737) | enrollment in **¡Por Vida!** |
| Victim/Survivor (180) | enrollment in **Stop The Hate** |
| Client (122) | enrollment in **Elevate Youth Prevention** |
| Parent (67) | **family link** (member of the youth's Family), no enrollment |

- Case Status `Active` → enrollment stays Active. `Closed` / `Inactive` /
  `Waitlist` → `LeaveProgram` dated by the person's **last note date** (fallback:
  import day, flagged in the audit).
- Assignee / note Author names → `User` accounts (placeholder
  `casebook-<slug>@import.invalid` emails, random passwords). Staff named in
  `ACTIVE_STAFF="Name One,Name Two"` at import time stay enabled; everyone else
  is **disabled** — authorship preserved without door keys (owner decision).
  The audit prints the staff list with row counts to build that env var from.
- Imported ProgressNotes carry the "Imported from Casebook" note type + location
  (provenance filterable). Note dedupe compares decrypted subject+narrative in
  Ruby inside the (client, author, date, type) candidate set — the narrative
  columns are non-deterministically encrypted, so a SQL WHERE can never match.
- Case Name / Case Type ('Direct Services' on every row) → Imported-from-Casebook
  form on the enrollment record.

## Client Notes → `ProgressNote` + tracking entries

Every note becomes a **ProgressNote** (F5): Contact Start Date → `date`,
Narrative → `response`, Subject prefixed into `additional_note`, Author →
`user_id` (the staff mapping above), Contact Method → note meta.

The **Subject classifier** (`Casebook::SubjectClassifier`) additionally creates a
tracking entry (with `entry_date` = Contact Start Date — the Y2 column) when the
Subject matches:

| Subject pattern | Tracking entry |
|---|---|
| `Week N <curriculum>[: <lesson>]` ("Week 2 Joven Noble: Palabra") | that curriculum's **Session Attendance** |
| curriculum token ANYWHERE, exactly one match ("Joven Noble Group", "Joven Noble 6: El Otro Yo", "Girasol Intro") | **Session Attendance**; session # only from `N:` (a `2/11/25` date never counts) |
| bare `Week N` | resolved by the applier against the client's SOLE cohort enrollment; ambiguous → ProgressNote only |
| `1:1 check-in`, `1-1 Check in[: …]`, `Check-in` | ¡Por Vida! **Mentorship Contact** |
| `Case management`, `Case Mgmt` | ¡Por Vida! **Case Management Contact** |
| `Navigation`, `Food Resource/assistance`, `Referral for Food` | Stop The Hate **Navigation / Case Mgmt / Referral** |
| `Pre/Post-Assessment` (any spacing, "…and Intake") | audit-listed (assessments not auto-created) |
| anything else | ProgressNote only |

Sessions IMPLY cohort enrollment (a Joven Noble session note is Joven Noble
participation — the enrollment is created if missing). Contact-type trackings do
NOT imply enrollment: a Student's one-off Navigation note never mints a Stop The
Hate enrollment; without an existing enrollment the entry is skipped and only
the ProgressNote lands.

Against the real exports (2026-07-31 read-only audit): **53.1% of 8,045 notes
classify** (4,273 tracking entries). The biggest unclassified buckets — Cultura
Club (140), Celebracion (83), Closing Notes (55), Ancestral teachings (48) —
need OCA's word on which program they belong to; the classifier table grows in
this file + `subject_classifier.rb` before the production run.

`casebook:audit` prints classifier coverage (% of 8,045 classified) and the
distinct unclassified Subjects (subject strings are service labels, not PII) so
the table can grow before the real run.

## Providers Data Table → `Agency`

Provider Name → `name`; the rest (license/status/type/capacity/address) →
Imported-from-Casebook form. provider_id = idempotency key.

## Cross-checks (audit only)

- Service Notes "Note-level Details" (4,587): no person column — totals by
  Service Type are compared against classified-tracking totals (PV!/STH:/EYC:
  prefixes map to the three programs).
- Population Served (721 case-person rows): row count reconciled against Cases
  Data Table joins.

## Runbook (production youth box, later turn)

```sh
# 1. audit (read-only, aggregates only)
docker compose run --rm app bundle exec rake casebook:audit CASEBOOK_DIR=/imports/oca
# 2. dry-run import (no writes; prints per-entity would-create counts)
docker compose run --rm app bundle exec rake casebook:import CASEBOOK_DIR=/imports/oca
# 3. the real thing — triple-gated
docker compose run --rm -e RAILS_ENV=production app \
  bundle exec rake casebook:import CASEBOOK_DIR=/imports/oca TENANT=oca CONFIRM=1
```
