# Youth Development flavor (One Community Action)

CaseLight's second **flavor** — a per-deployment configuration for youth-development
work, developed with One Community Action of Santa Maria Valley (ocasmv.org). A flavor
changes vocabulary, navigation, taxonomy, and reports **without forking the code**: the
same core application serves every flavor. See `OPERATIONS.md` (Flavors section) for the
mechanism and the demo-box flip runbook, `docs/casebook-mapping.md` for the data
migration, and the owner-side `YOUTH-FLAVOR-RESEARCH.md` for the org research.

> **One server per flavor.** A deployment is pinned to a single flavor via `FLAVOR=`
> (whitelisted `resettlement | youth`). Tenants on the same box share the flavor; it is a
> deploy-time choice, not a per-tenant toggle. This is deliberate: ros-apartment gives each
> tenant full customization of everything in the **database** (forms, program streams,
> domains, reference lists) but nothing in **code** (vocabulary, navigation, reports) — so
> code-level differences are carried by the flavor, one box per flavor.

## What the flavor changes

### Vocabulary
`config/flavors/youth/en.yml` overlays the base locale (appended after `config/locales`,
last-wins): Youth Development Dashboard, FAMILIES / YOUTH / SERVICE CONTACTS tiles,
side-menu Youth + Families. The base stays vertical-neutral and every overlay key is
deletable.

### Navigation
The youth flavor adds two sidebar entries the default (resettlement) nav doesn't have,
gated on `config.x.flavor == 'youth'` in `app/views/layouts/_side_menu.haml`:

- **Schools** — a young person's *education* record: attendance, GPA, academic check-ins.
- **Sites** — the *delivery* locations that host programs.

A campus is usually **both** a School and a Site (same name, two `Agency.kind` rows).
Schools never host programs; Sites do. This is the first structural (not merely locale)
flavor branch in the view layer.

### Schools & Sites
Shipped across the school batches (SCH1–4 #276–#279, HUB1–2 #280–#281, S1–S4 #284) and the
**School/Site split** (#294/#296/#297, 2026-08-13):

- **Schools** are `Agency.kind == 'school'`. Each opens a hub with **Overview / Roster /
  Cohorts** tabs. The Roster is one row per caseload youth linked to the school (programs,
  last contact, GPA, attendance %, and a **"Check-in overdue"** flag when the latest
  academic check-in is missing or older than 45 days).
- **Report cards** are the **Academic Check-in (Aeries)** tracking on **¡Por Vida!** —
  GPA (stored ×100), cumulative credits, A-G on track, school-day attendance %, discipline
  incidents, and IEP/SST notes. Entered as a per-school **batch grid**
  (`/schools/:id/report_cards/new` — latest values shown as placeholders, blank rows
  skipped) and edited from the **cards-on-file** index (`/schools/:id/report_cards`).
  There is no top-level report-cards route; they exist only nested under a school.
- **Cohort roll call** records per-session **Session Attendance** — Present / Absent /
  Excused, none pre-selected — deduped on (enrollment, tracking, date, **session number**)
  so two sessions can be held in a day and a corrected date won't double-count.
- **Cohort instances** are a curriculum running at one school for one term. Sessions are
  numbered `1..N` (El Joven Noble 12, Girasol 13); every slot renders whether held or
  **"Not held yet"**; a **completer** is a youth who attended **≥ 75%** of sessions. Cohort
  math is centralized in `app/classes/cohorts.rb` (`Schools::CohortInstance`,
  `Schools::Roster`, `Schools::CohortCards`).
- **Sites** are `Agency.kind == 'site'` and host programs via `AgencyProgramStream`
  (`youth:seed_sites`). `youth:seed_schools` **purges** any program links from school
  agencies — program *delivery* belongs to Sites, education tracking to Schools.
- **Linking:** `youth:link_schools` creates `AgencyClient` rows from each youth's
  client-level **"School"** quantitative (school of attendance). The older
  `link_schools_from_sites` path was removed in the split.

### Taxonomy (`lib/tasks/youth_taxonomy.rake`, dispatched by `flavor:seed`)
Every task is guarded by `youth_flavor!` (aborts on any non-youth box).

- **Forms** (sensitivity in parentheses):
  - Client — Guardian & Emergency Contacts (**restricted**), Youth Safety Plan
    (**restricted**), Consents & Releases, Referral & Intake (carries the *Student ID
    (Aeries)* matching key), Hate Incident Record (**restricted**; the statutory bias
    categories, Penal Code 422.55).
  - Family — Household & Family Context, Family Engagement Log, Custody & Pickup
    Authorization (**restricted**).
- **Programs** (all multi-tracking): ¡Por Vida! (Case Management / Mentorship / Academic
  Check-in (Aeries) / Workshop / SMART Goals), Stop The Hate (Navigation / Wellness &
  Healing / Safety Planning / Court Accompaniment), Elevate Youth Prevention, R.A.I.C.E.S.,
  and six cohort curricula (El Joven Noble, Girasol, Cara y Corazón, Nurturing Our Futures,
  Susto y Limpia, Mi Palabra), each with a weekly **Session Attendance** tracking.
- **Reference lists:** Preferred Language (incl. Mixteco, Zapoteco, Triqui, Purépecha),
  School, Grade Level, Race, Ethnicity, Poverty Level.
- **Assessment domains:** the CASEL five (Self-Awareness, Self-Management, Social
  Awareness, Relationship Skills, Responsible Decision-Making) plus School Engagement, on a
  4-point Emerging → Consistent scale; `ASSESSMENT_MIN_INTERVAL_DAYS=84` for the 12-week
  pre/post cadence.

### Reports
The report registry (`app/classes/reports/registry.rb`) is scoped to the active flavor. On
top of the shared worker/manager packs, the youth list adds:

- **My youth engagement** (worker), **Enrollment & dosage** (manager), **Cohort
  completion** (manager);
- **Unduplicated youth served**, **SEL pre/post outcomes**, **Stop The Hate quarterly**
  (bias categories per Penal Code 422.55), **Academic partner report**, **Demographics
  profile**, and **Funder attribution** (all leadership tier).

Tier controls *which report* a role can open; every report additionally re-scopes rows
through `Client.accessible_by(current_ability)`, so RBAC still controls *which rows*.
There is no youth *employment* report — employment outcomes are resettlement-only.

### Demo data
`youth:seed_demo_youth` (SEED_DEMO-gated) seeds synthetic Demo-prefixed youths, a cohort
with backdated session entries, and one Stop The Hate incident. Demo boxes only — real
records are gated by `SECURITY.md`.

## Flavor lock

Three enforcement points, pinned both directions by `spec/lib/flavor_lock_spec.rb`:

1. **Routes** — every school/site route is wrapped in a per-request constraint
   (`config.x.flavor == 'youth'`). A resettlement box has no school routes *at all* — they
   raise `RoutingError`, not merely hide a sidebar entry.
2. **Seed rakes** — `youth_flavor!` aborts every `youth:*` task and `aeries:sync` on any
   non-youth box.
3. **Report registry** — the youth report slugs are absent from the resettlement registry;
   a cross-flavor lookup raises `RecordNotFound`.

## Why it's shaped this way

OCA's pain is **reporting completeness for grant retention** (BSCC Stop The Hate, EYC):
their Casebook export shows Poverty Level ~69% blank, Education ~85% blank, service units
~98.5% blank, and services logged as free-text note subjects. The flavor turns each of
those into structure — quantitative dropdowns instead of blanks, per-tracking service logs
with a backdatable `entry_date` (honest late entry), session attendance per cohort
curriculum, and academic check-ins — and the importer's audit prints the blank-rate
baseline they improve from.

## Verification

The flavor is covered by the suite that runs on every PR (`.github/workflows/ci.yml`): the
taxonomy seed specs (forms/sensitivity, programs/trackings, idempotency, guarded domain
reconcile, backdated demo), the flavor mechanism and `spec/lib/flavor_lock_spec.rb` (the
three-point lock, both directions), the school-surface request specs (hub, roster,
report-card entry, roll call, cohort instances, and the Sites surface), the youth report
classes (`app/classes/reports/youth/`), and the Casebook importer specs (reader,
classifier, gated apply, idempotent re-apply).

## Open asks for OCA

1. Which program do **Cultura Club** (140 notes), **Celebracion** (83) and **Ancestral
   teachings** (48) belong to? (The classifier table grows in `docs/casebook-mapping.md`
   and `subject_classifier.rb`.)
2. Are **parents their own participants** (Cara y Corazón cohorts for adults) or household
   members only? Import currently links them as family members without enrollments.
3. **SMJUHSD data authorization** for Aeries-sourced academic check-ins (GPA / credits /
   attendance land in the Academic Check-in tracking).
4. Active staff list at import time (`ACTIVE_STAFF=` — everyone else lands disabled).
5. The one collided name pair and 42 unmatched case rows from the audit need a human
   decision before the production import.

## Production import (later turn, on the youth box only)

See the runbook in `docs/casebook-mapping.md` — audit → dry run → triple-gated import
(`CONFIRM=1` + `RAILS_ENV=production` + explicit `TENANT=`). Never on the demo box; demo
youth data is synthetic only.
