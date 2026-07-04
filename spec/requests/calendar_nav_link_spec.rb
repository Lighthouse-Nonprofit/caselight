# frozen_string_literal: true
require 'rails_helper'

# Regression guard (SLO4HOME): the internal calendar must be reachable from the nav for EVERY
# authenticated user, regardless of the Google-sync opt-in (User#calendar_integration, default false).
# The calendar nav link used to be gated behind `current_user.calendar_integration?`, which hid the
# ONLY path to the calendar for anyone who had not enabled Google Calendar sync (i.e. almost everyone) --
# that is what made the calendar appear "missing" on the box. The Google Sync button itself stays gated
# inside calendars/index; only the nav link is unconditional.
RSpec.describe 'Calendar nav link visibility', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  it 'renders the calendar nav link when calendar_integration is OFF (the default)' do
    user = create(:user, roles: 'admin', password: password, password_confirmation: password)
    user.update_column(:calendar_integration, false) if user.has_attribute?(:calendar_integration)
    expect(user.calendar_integration?).to be_falsey # non-vacuous: the Google-sync flag is off

    sign_in_as(user)
    get clients_path

    expect(response).to have_http_status(:ok)
    expect(response.body).to match(%r{href=["']/calendars(\?[^"']*)?["']}) # nav link to the calendar
    expect(response.body).to include('fa-calendar fa-fw')                  # the generic calendar icon
  end
end
