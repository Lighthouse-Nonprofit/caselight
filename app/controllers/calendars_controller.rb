require 'google/apis/calendar_v3'
require 'signet/oauth_2/client'

class CalendarsController < AdminController
  # Phase 5.6 (AC-3) allowlist (whole-controller): Google Calendar OAuth + one-way sync. Every action
  # (redirect/callback/index/sync) operates strictly on current_user / session -- no addressable resource,
  # no other-user data. Behind authenticate_user! (AdminController).
  skip_authorization_check

  # One-way sync of a user's client Tasks into their Google Calendar via OAuth2.
  # Credentials come from ENV (GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET); the feature
  # is dormant until those are set and a user enables it (users.calendar_integration).
  # Modernized for Rails 7.1 / Ruby 3.3 on the google-apis-calendar_v3 split gem
  # (was the monolithic google-api-client ~> 0.10; the Signet/CalendarV3 API is unchanged).

  def redirect
    client = oauth_client(authorization_uri: 'https://accounts.google.com/o/oauth2/auth',
                          scope: Google::Apis::CalendarV3::AUTH_CALENDAR,
                          redirect_uri: callback_url)
    redirect_to client.authorization_uri.to_s, allow_other_host: true
  end

  def callback
    if params[:error].present?
      session[:sync] = nil
      redirect_to calendars_path
    else
      client = oauth_client(token_credential_uri: 'https://accounts.google.com/o/oauth2/token',
                            redirect_uri: callback_url,
                            code: params[:code])
      response = client.fetch_access_token!
      current_user.update(expires_at: DateTime.now + response['expires_in'].seconds)
      session[:authorization] = response
      redirect_to calendars_path
    end
  end

  def index
    if session[:sync] == 'connected'
      client = oauth_client(token_credential_uri: 'https://accounts.google.com/o/oauth2/token')
      client.update!(session[:authorization])
      calendars = push_events(client)
      session[:sync] = nil
      flash_sync_result(calendars)
    end
  end

  def sync
    if session[:authorization].blank? || current_user.expires_at < DateTime.now.in_time_zone
      session[:sync] = 'connected'
      redirect_to redirect_path
    else
      client = oauth_client(token_credential_uri: 'https://accounts.google.com/o/oauth2/token')
      client.update!(session[:authorization])
      calendars = push_events(client)
      flash_sync_result(calendars)
    end
  end

  private

  def oauth_client(options = {})
    Signet::OAuth2::Client.new({ client_id: ENV['GOOGLE_CLIENT_ID'],
                                 client_secret: ENV['GOOGLE_CLIENT_SECRET'] }.merge(options))
  end

  def push_events(client)
    service = Google::Apis::CalendarV3::CalendarService.new
    service.authorization = client
    calendars = current_user.calendars.sync_status_false
    calendars.each do |event_list|
      event = Google::Apis::CalendarV3::Event.new(
        start: Google::Apis::CalendarV3::EventDateTime.new(date: event_list.start_date.to_date.to_s),
        end: Google::Apis::CalendarV3::EventDateTime.new(date: event_list.end_date.to_date.to_s),
        summary: event_list.title
      )
      service.insert_event('primary', event)
      event_list.update(sync_status: true)
    end
    calendars
  end

  def flash_sync_result(calendars)
    if calendars.present?
      redirect_to calendars_path, notice: t('add_event_success')
    else
      redirect_to calendars_path, alert: t('existed_event')
    end
  end
end
