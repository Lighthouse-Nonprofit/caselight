module Api
  class CalendarsController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:find_event, :client_programs]): both are self-scoped AJAX feeds
    # with no CanCan-addressable resource of their own -- find_event serves Task.of_user(current_user)
    # (the personal lens; Task's CanCan rule is deliberately unscoped so accessible_by would leak the
    # whole org), and client_programs re-checks Client.accessible_by(current_ability) before answering.
    skip_authorization_check only: [:find_event, :client_programs]

    # Data-task batch (2026-07): the FullCalendar feed is TASK-NATIVE. The old materialized
    # `calendars` table (one row per task per user, end = start + 1 day always) is gone with
    # its drift bugs — this reads the user's tasks for the VISIBLE RANGE (FC sends start/end)
    # and emits FC6-ready events with an EXPLICIT allDay flag:
    #   all-day: date-only `start`, NO `end` (avoids FC's exclusive-end fencepost)
    #   timed:   offset-less local ISO (%FT%T) — app zone wall time; FC renders as-is
    # Rendered as a pre-serialized JSON STRING (the program_clients AMS dodge below).
    def find_event
      range = feed_range
      tasks = Task.of_user(current_user)
                  .where(completion_date: range)
                  .includes(:client, :domain)
      render json: tasks.map { |task| event_json(task) }.to_json
    end

    # Powers the "program" dropdown in the calendar's date-click task modal — FLIPPED per the
    # owner (2026-07-31): pick the PERSON first, then the program they're in. The person list is
    # server-rendered into the modal from the same accessible_by scope; this endpoint re-checks the
    # boundary, so a probed client_id outside the caller's caseload answers [] — indistinguishable
    # from a person with no active programs. (Task creation itself is re-gated by
    # Client::TasksController#create via the same accessible_by lookup, so a forged client_id can
    # never create a cross-caseload task even if this list were bypassed.)
    def client_programs
      client = Client.accessible_by(current_ability).find_by(id: params[:client_id])
      programs =
        if client
          # .order(:name), not .ordered — the lower(name) expression isn't in the DISTINCT
          # select list and PG rejects the pair
          ProgramStream.joins(:client_enrollments)
                       .where(client_enrollments: { client_id: client.id, status: 'Active' })
                       .distinct.order(:name)
        else
          ProgramStream.none
        end
      # .to_json (not a bare array): ActiveModel::Serializers intercepts `render json: <Array>` and raises
      # CannotInferRootKeyError on an EMPTY collection. Rendering a pre-serialized JSON string bypasses AMS.
      render json: programs.map { |program| { id: program.id, name: program.name } }.to_json
    end

    private

    # FC sends ISO start/end for the visible window; a missing/garbled range falls back to a
    # sane month-ish window rather than the whole history.
    def feed_range
      from = Date.parse(params[:start]) rescue (Time.zone.today - 1.month)
      to   = Date.parse(params[:end])   rescue (Time.zone.today + 1.month)
      from..to
    end

    def event_json(task)
      bucket =
        if task.completed? then 'task-completed'
        elsif task.completion_date < Time.zone.today then 'task-overdue'
        elsif task.completion_date == Time.zone.today then 'task-today'
        else 'task-upcoming'
        end
      base = {
        id: task.id,
        title: "#{task.domain&.name} - #{task.name}",
        url: client_tasks_path(task.client),
        classNames: [bucket],
        durationEditable: task.timed?
      }
      if task.timed?
        base.merge(start: task.starts_at.strftime('%FT%T'),
                   end: task.ends_at.strftime('%FT%T'),
                   allDay: false)
      else
        base.merge(start: task.completion_date.iso8601, allDay: true)
      end
    end
  end
end
