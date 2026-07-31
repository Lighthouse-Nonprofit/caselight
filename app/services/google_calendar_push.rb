# Data-task batch C5 — the REBUILT one-way Task -> Google Calendar push (the legacy one
# retired in C2; see REMOVED-FEATURES.md 2026-07-30). Owner decision: "retire and rebuild,
# now — rather than adapt something that is broken, that allows us to ensure secure calls."
#
# Design:
#   * DORMANT until GOOGLE_CLIENT_ID/GOOGLE_CLIENT_SECRET exist (the SMTP feature-flip
#     pattern) — enabled? gates the Task hooks, the worker, AND the connect UI.
#   * Per-user offline access: the refresh token lives encrypted on users.google_refresh_token
#     (non-deterministic encrypts, ENCRYPTION_TIERS tier 6, paper_trail-skipped).
#   * Honest state: GoogleTaskEvent rows map (task, user) -> google_event_id, so updates and
#     deletes address the REAL event — no title/date string matching.
#   * Timed-aware: timed tasks push EventDateTime(date_time:) with the app zone; all-day
#     tasks push date: with Google's exclusive end convention (start + 1 day).
#   * All network calls happen in GoogleCalendarPushWorker (Sidekiq), never in-request.
require 'google/apis/calendar_v3'

class GoogleCalendarPush
  CALENDAR_ID = 'primary'
  SCOPE       = 'https://www.googleapis.com/auth/calendar.events'
  AUTH_URI    = 'https://accounts.google.com/o/oauth2/auth'
  TOKEN_URI   = 'https://oauth2.googleapis.com/token'

  # DORMANT until real credentials exist. .env.example (and the pilot box) carry the literal
  # string "nil" for these — the same trap SENDER_EMAIL fell into — so treat 'nil' as unset.
  def self.enabled?
    configured?(ENV['GOOGLE_CLIENT_ID']) && configured?(ENV['GOOGLE_CLIENT_SECRET'])
  end

  def self.configured?(value)
    value.present? && value.strip.downcase != 'nil'
  end

  # --- OAuth (CalendarsController#google_auth / #google_callback) ---------------------

  def self.authorization_url(state:, redirect_uri:)
    client = oauth_client(redirect_uri: redirect_uri)
    client.state = state
    # offline + consent => Google returns a refresh token on every connect, not just the first
    client.authorization_uri(access_type: 'offline', prompt: 'consent').to_s
  end

  # Exchange the callback code; returns the refresh token (nil if Google withheld one).
  def self.exchange_code(code, redirect_uri:)
    client = oauth_client(redirect_uri: redirect_uri)
    client.code = code
    client.fetch_access_token!
    client.refresh_token
  end

  def self.oauth_client(redirect_uri:)
    Signet::OAuth2::Client.new(
      authorization_uri: AUTH_URI,
      token_credential_uri: TOKEN_URI,
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      scope: SCOPE,
      redirect_uri: redirect_uri
    )
  end

  # --- Push (GoogleCalendarPushWorker) -------------------------------------------------

  def initialize(user)
    @user = user
  end

  # Create-or-update the user's event for this task.
  def upsert(task)
    record = GoogleTaskEvent.find_by(task_id: task.id, user_id: @user.id)
    if record
      begin
        service.update_event(CALENDAR_ID, record.google_event_id, event_for(task))
      rescue Google::Apis::ClientError => e
        raise unless gone?(e)
        # The user deleted the event on the Google side — drop the stale state and recreate.
        record.destroy
        record = nil
      end
    end
    return if record

    created = service.insert_event(CALENDAR_ID, event_for(task))
    GoogleTaskEvent.create!(task_id: task.id, user_id: @user.id, google_event_id: created.id)
  end

  # Delete by event id (the task row — and its state rows — are already gone by push time).
  def remove(google_event_id)
    return if google_event_id.blank?
    service.delete_event(CALENDAR_ID, google_event_id)
  rescue Google::Apis::ClientError => e
    raise unless gone?(e) # already deleted on the Google side = success
  end

  private

  def gone?(error)
    [404, 410].include?(error.status_code)
  end

  def event_for(task)
    event = Google::Apis::CalendarV3::Event.new(
      summary: [task.domain&.name, task.name].compact.join(' - ')
    )
    if task.timed?
      event.start = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: task.starts_at.iso8601, time_zone: Time.zone.name
      )
      event.end = Google::Apis::CalendarV3::EventDateTime.new(
        date_time: task.ends_at.iso8601, time_zone: Time.zone.name
      )
    else
      # Google all-day events use an EXCLUSIVE end date.
      event.start = Google::Apis::CalendarV3::EventDateTime.new(date: task.completion_date.iso8601)
      event.end   = Google::Apis::CalendarV3::EventDateTime.new(date: (task.completion_date + 1).iso8601)
    end
    event
  end

  def service
    @service ||= Google::Apis::CalendarV3::CalendarService.new.tap do |s|
      s.authorization = authorizer
    end
  end

  def authorizer
    client = Signet::OAuth2::Client.new(
      token_credential_uri: TOKEN_URI,
      client_id: ENV['GOOGLE_CLIENT_ID'],
      client_secret: ENV['GOOGLE_CLIENT_SECRET'],
      refresh_token: @user.google_refresh_token
    )
    client.fetch_access_token!
    client
  end
end
