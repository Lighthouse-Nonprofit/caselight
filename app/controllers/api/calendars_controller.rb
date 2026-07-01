module Api
  class CalendarsController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:find_event]): returns current_user.calendars.as_json only --
    # self-scoped AJAX feed, no authorizable resource. (find_event is the only implemented action; the
    # RESTful routes from `resources :calendars` are inert and the hard-CI guard skips them via
    # action_methods intersection.)
    skip_authorization_check only: [:find_event]

    # Feeds the fullCalendar widget on calendars#index. Explicit { calendars: ... } root
    # (no CalendarSerializer exists; AMS 0.10's :json adapter would not root a bare relation
    # the way AMS 0.9 did, and calendars/index.coffee reads `json.calendars`).
    def find_event
      render json: { calendars: current_user.calendars.as_json }
    end
  end
end
