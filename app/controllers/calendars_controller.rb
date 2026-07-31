class CalendarsController < AdminController
  # Phase 5.6 (AC-3) allowlist: index renders the FullCalendar shell only; event data flows
  # through Api::CalendarsController#find_event (Task.of_user — the personal lens).
  skip_authorization_check only: [:index]

  # Data-task batch (2026-07): the legacy one-way Google push (session-token OAuth, all-day
  # events only, state on the dropped `calendars` table) is RETIRED — see REMOVED-FEATURES.md.
  # C5 below rebuilds it clean: per-(task,user) sync state, timed events, encrypted refresh
  # tokens, and a `state`-checked callback. All three actions operate on current_user ONLY and
  # authorize! :update, Task in-body (every task-managing role holds it; strategic overviewer
  # correctly does not) — listed in the AC-3 guard's IN_BODY_AUTHORIZE allowmap.
  def index
  end

  def google_auth
    authorize! :update, Task
    return redirect_to calendars_path, alert: t('.disabled', default: 'Google Calendar sync is not configured for this installation.') unless GoogleCalendarPush.enabled?

    session[:google_oauth_state] = SecureRandom.hex(32)
    redirect_to GoogleCalendarPush.authorization_url(
      state: session[:google_oauth_state],
      redirect_uri: google_redirect_uri
    ), allow_other_host: true
  end

  def google_callback
    authorize! :update, Task
    return redirect_to calendars_path, alert: t('.disabled', default: 'Google Calendar sync is not configured for this installation.') unless GoogleCalendarPush.enabled?

    # Anti-CSRF: the state we sent must round-trip. delete() so a replayed callback fails.
    expected_state = session.delete(:google_oauth_state)
    if params[:state].blank? || expected_state.blank? || !ActiveSupport::SecurityUtils.secure_compare(params[:state].to_s, expected_state)
      return redirect_to calendars_path, alert: t('.state_mismatch', default: 'Google sign-in could not be verified — please try connecting again.')
    end
    return redirect_to calendars_path, alert: t('.denied', default: 'Google did not grant calendar access.') if params[:code].blank?

    token = GoogleCalendarPush.exchange_code(params[:code], redirect_uri: google_redirect_uri)
    if token.present?
      current_user.update!(google_refresh_token: token)
      redirect_to calendars_path, notice: t('.connected', default: 'Google Calendar connected — new and updated tasks will sync.')
    else
      redirect_to calendars_path, alert: t('.no_token', default: 'Google did not return an offline credential — please try connecting again.')
    end
  rescue Signet::AuthorizationError
    redirect_to calendars_path, alert: t('.exchange_failed', default: 'Google rejected the sign-in — please try connecting again.')
  end

  def google_disconnect
    authorize! :update, Task
    current_user.update!(google_refresh_token: nil)
    redirect_to calendars_path, notice: t('.disconnected', default: 'Google Calendar disconnected. Already-synced events stay on your Google calendar.')
  end

  private

  # The redirect URI must byte-match the one registered in the Google console on BOTH the
  # consent redirect and the code exchange — locale: nil keeps the default_url_options
  # ?locale=en query param out of it.
  def google_redirect_uri
    google_callback_calendars_url(locale: nil)
  end
end
