class CalendarsController < AdminController
  # Phase 5.6 (AC-3) allowlist: index renders the FullCalendar shell only; event data flows
  # through Api::CalendarsController#find_event (Task.of_user — the personal lens).
  skip_authorization_check only: [:index]

  # Data-task batch (2026-07): the legacy one-way Google push (session-token OAuth, all-day
  # events only, state on the dropped `calendars` table) is RETIRED — see REMOVED-FEATURES.md.
  # C5 rebuilds it clean: per-(task,user) sync state, timed events, encrypted refresh tokens.
  def index
  end
end
