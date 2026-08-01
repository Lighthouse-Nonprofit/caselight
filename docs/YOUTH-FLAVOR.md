# Youth Development flavor (One Community Action)

The second CaseLight flavor (batch Y1–Y6, PRs #264–#269), built for One
Community Action of Santa Maria Valley (ocasmv.org) — racial-justice mission,
youth-development programming. Research memo: the owner-side
`YOUTH-FLAVOR-RESEARCH.md`; Casebook migration: `docs/casebook-mapping.md`;
flavor mechanics + flip runbook: `OPERATIONS.md` (Flavors section).

## What the flavor changes

- **Vocabulary** (`config/flavors/youth/en.yml`): dashboard = Youth Development
  Dashboard, FAMILIES / YOUTH / SERVICE CONTACTS tiles, side menu Youth +
  Families. Base stays vertical-neutral; every overlay key is deletable.
- **Taxonomy** (`lib/tasks/youth_taxonomy.rake`, dispatched by `flavor:seed`):
  - Forms: Guardian & Emergency Contacts (restricted), Youth Safety Plan
    (restricted), Hate Incident Record (restricted; the 7 statutory bias
    categories), Consents & Releases, Referral & Intake; family Household &
    Family Context. Sensitivity INLINE — no separate classify pass.
  - Programs (all multi-tracking): ¡Por Vida! (case mgmt / mentorship /
    Aeries academic check-in / workshops / SMART goals), Stop The Hate
    (navigation, wellness & healing, safety planning, accompaniment), Elevate
    Youth Prevention, R.A.I.C.E.S., and six cohort curricula (El Joven Noble,
    Girasol, Cara y Corazón, Nurturing Our Futures, Susto y Limpia, Mi
    Palabra) with School Site + Term enrollment and weekly Session Attendance.
  - Lists: Preferred Language (incl. Mixteco, Zapoteco, Triqui, Purépecha),
    School Site, Grade Level, Race, Ethnicity, Poverty Level.
  - Assessment domains: CASEL five (Y1–Y5) + School Engagement (Y6);
    `ASSESSMENT_MIN_INTERVAL_DAYS=84` for the 12-week pre/post cadence.
- **Demo data** (`youth:seed_demo_youth`, SEED_DEMO-gated): synthetic
  Demo-prefixed youths, a Girasol cohort with backdated session entries, one
  Stop The Hate incident.

## Why it's shaped this way

OCA's pain is **reporting completeness for grant retention** (BSCC Stop The
Hate, 21APR/EYC): their Casebook export shows Poverty Level 69% blank,
Education 85% blank, service units 98.5% blank, and services logged as
free-text note subjects. The flavor turns each of those into structure:
quantitative dropdowns (two clicks instead of a blank), per-tracking service
logs with a backdatable `entry_date` (honest late entry), session attendance
per cohort curriculum, and the importer's audit prints the blank-rate baseline
they improve from.

## Verification (all green locally)

- `spec/lib/tasks/youth_taxonomy_spec.rb` — 14 examples (forms/sensitivity,
  programs/trackings, idempotency, guarded domain reconcile, backdated demo).
- `spec/lib/flavor_spec.rb` — mechanism + overlay content contract.
- `spec/lib/tasks/casebook_import_spec.rb` — 6 examples (reader, classifier,
  aggregate-only audit, gate refusal, full mapping apply, idempotent re-apply).
- `spec/features/youth_program_flow_spec.rb` — multi-tracking dropdown +
  backdated entry through the real UI; restricted-form sensitivity by role.

## Open asks for OCA

1. Which program do **Cultura Club** (140 notes), **Celebracion** (83) and
   **Ancestral teachings** (48) belong to? (Classifier table grows in
   `docs/casebook-mapping.md` + `subject_classifier.rb`.)
2. Are **parents own participants** (Cara y Corazón cohorts for adults) or
   household members only? Import currently links them as family members
   without enrollments.
3. **SMJUHSD data authorization** for Aeries-sourced academic check-ins
   (GPA/credits/attendance land in the Academic Check-in tracking).
4. Active staff list at import time (`ACTIVE_STAFF=` — everyone else lands
   disabled).
5. The one collided name pair + 42 unmatched case rows from the audit need a
   human decision before the production import.

## Production import (later turn, on the youth box only)

See the runbook in `docs/casebook-mapping.md` — audit → dry run → triple-gated
import (`CONFIRM=1` + `RAILS_ENV=production` + explicit `TENANT=`). Never on
the demo box; demo youth data is synthetic only.
