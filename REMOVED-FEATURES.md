# Removed features

## 2026-07-30 — legacy Google Calendar push + the materialized `calendars` table (data-task batch, C2)

The FullCalendar feed is task-native now (`Api::CalendarsController#find_event` serves
`Task.of_user` for the visible range, with explicit all-day/timed shapes). That deleted
the materialized `calendars` table — one row per task per user, populated only on create,
`end = start + 1 day` always — and its drift-bug class (rows went stale on every task
edit/delete for non-Google users, were matched by title+dates string equality across
users, and forced every event to render all-day).

The table was also the state store for the legacy ONE-WAY Google Calendar push
(session-token OAuth in `CalendarsController` redirect/callback/sync, all-day
`EventDateTime(date:)` events only, `sync_status` per row). Retired with it, per the
owner: "retire and rebuild, now — rather than adapt something that is broken, that
allows us to ensure secure calls."

**Rebuild recipe (lands as C5 in the same batch):** a `google_task_events`
(task_id, user_id, google_event_id) state table with FKs + unique pair; a
`GoogleCalendarPush` service doing create/update/delete with
`EventDateTime.new(date_time:)` for timed tasks and `date:` for all-day; OAuth with
proper authorization on the controller actions, a `state` anti-CSRF param on the
callback, and the refresh token stored encrypted; dormant behind
GOOGLE_CLIENT_ID/SECRET env presence + the per-user `calendar_integration` flag.

The running ledger of upstream-OSCaR features CaseLight has removed (or removed and
re-added), for anyone chasing a dangling reference. The original REMOVED-FEATURES.md from
the 2026-06 modernization was documented in the project memory but never landed in the
tree — several long-standing comments cite it — so this file recreates the ledger and
picks it up going forward.

## 2026-07-29 — legacy `client_enrolled_*` route family (investor UX round, P2)

Upstream OSCaR carried TWO parallel route/controller/view families for program
enrollments: `client_enrollments` + `client_enrollment_trackings` + `leave_programs`
(the "modern" family) and `client_enrolled_programs` + `client_enrolled_program_trackings`
+ `leave_enrolled_programs` (the legacy twins — near-byte-identical views, cross-wired
redirects, duplicated i18n blocks and grids). The consolidated Programs tab (P1) moved
everything onto the modern family, including the tracking/exit `new`/`create` actions the
modern controllers never had.

Removed in P2: the three legacy controllers, ~20 view templates across three directories,
`ClientEnrolledProgramTrackingGrid`, the legacy branches in the form-builder attachment
concern/helpers, the `client_enrolled_program_id` param fallbacks, three `HUB_TABS`
entries, the legacy en.yml blocks, and the legacy SCSS body-id selectors.

Old `/clients/:id/client_enrolled_programs/**` URLs now 404 (internal app, owner-approved
— no redirect shims). The modern family's collection `report` URL 301s to the Programs
tab's pane deep link (`/clients/:id/client_enrollments?program_stream_id=`).

## 2026-07-28 — Cambodia government-reports feature + wkhtmltopdf stack (POAM-019)

`GovernmentReportsController`, its views/model/decorator/helper, `wicked_pdf`, the
archived-Qt-WebKit wkhtmltox binary and its Dockerfile block, the BS3 `pdf_design`
layout and vendored print CSS. Replaced by the warm Chromium/Ferrum `PdfRenderer`
surface (`app/classes/pdf_renderer.rb`) — per-flavor reporting builds on it. The orphan
`government_reports` table remains in the schema for a future cleanup migration.

## 2026-06 — modernization removals (recreated summary)

- **appsignal** — removed with the Rails-4.2-era monitoring wiring (PR #1 era).
- **Google Calendar sync** — removed during the upgrade, then RE-ADDED on
  `upgrade/rails-7.1` with `google-apis-calendar_v3` (the Gemfile/routes comments that
  cite this file). Task → Calendar sync lives behind the per-user Google flag.
- Various upstream API endpoints trimmed on `upgrade/rails-7.1`; the remaining `/api`
  endpoints are enumerated in `config/routes.rb` alongside their consumers.
