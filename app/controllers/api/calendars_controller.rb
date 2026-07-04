module Api
  class CalendarsController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:find_event, :program_clients]): both are self-scoped AJAX feeds
    # with no CanCan-addressable resource of their own -- find_event returns current_user.calendars, and
    # program_clients returns ONLY Client.accessible_by(current_ability) (so the caller can never see or
    # target a client outside their own authorization scope). The RESTful routes from `resources :calendars`
    # stay inert and the hard-CI guard skips them via the action_methods intersection.
    skip_authorization_check only: [:find_event, :program_clients]

    # Feeds the fullCalendar widget on calendars#index. Explicit { calendars: ... } root
    # (no CalendarSerializer exists; AMS 0.10's :json adapter would not root a bare relation
    # the way AMS 0.9 did, and calendars/index.coffee reads `json.calendars`).
    def find_event
      render json: { calendars: current_user.calendars.as_json }
    end

    # Powers the "person" dropdown in the calendar's date-click task modal. Given a program, returns the
    # active-enrolled clients IN THAT PROGRAM that the current user is authorized to see -- i.e. the exact
    # set of people this user could create a task for. accessible_by(current_ability) is the entire security
    # boundary: admin => all, case worker => their caseload, ec/fc/kc manager => their status + caseload.
    # (Task creation itself is re-gated by Client::TasksController#create via the same accessible_by lookup,
    # so a forged client_id can never create a cross-caseload task even if this list were bypassed.)
    def program_clients
      program = ProgramStream.find_by(id: params[:program_id])
      clients =
        if program
          Client.accessible_by(current_ability)
                .joins(:client_enrollments)
                .where(client_enrollments: { program_stream_id: program.id, status: 'Active' })
                .distinct
        else
          Client.none
        end
      # .to_json (not a bare array): ActiveModel::Serializers intercepts `render json: <Array>` and raises
      # CannotInferRootKeyError on an EMPTY collection. Rendering a pre-serialized JSON string bypasses AMS.
      render json: clients.map { |client| { id: client.id, name: client.name } }.to_json
    end
  end
end
