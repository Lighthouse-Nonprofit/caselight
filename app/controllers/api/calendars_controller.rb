module Api
  class CalendarsController < AdminController
    # Feeds the fullCalendar widget on calendars#index. Explicit { calendars: ... } root
    # (no CalendarSerializer exists; AMS 0.10's :json adapter would not root a bare relation
    # the way AMS 0.9 did, and calendars/index.coffee reads `json.calendars`).
    def find_event
      render json: { calendars: current_user.calendars.as_json }
    end
  end
end
