module Api
  class CalendarsController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:find_event, :program_clients]): both are self-scoped AJAX feeds
    # with no CanCan-addressable resource of their own -- find_event serves Task.of_user(current_user)
    # (the personal lens; Task's CanCan rule is deliberately unscoped so accessible_by would leak the
    # whole org), and program_clients returns ONLY Client.accessible_by(current_ability).
    skip_authorization_check only: [:find_event, :program_clients]

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
