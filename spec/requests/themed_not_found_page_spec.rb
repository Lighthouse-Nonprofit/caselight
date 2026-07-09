# frozen_string_literal: true
require 'rails_helper'

# Regression guard for ApplicationController's ActiveRecord::RecordNotFound rescue.
#
# The handler used to `render file: "#{Rails.root}/app/views/errors/404"` (NO extension). In Rails 7.2
# `render file:` demands a path to an actual file, so that raised
#   ArgumentError (File .../app/views/errors/404 does not exist)
# turning EVERY not-found (a mistyped or stale client slug, a since-deleted record) into an ugly 500
# stack trace instead of the themed 404 page that already existed. The fix mirrors the working
# errors/403 handler: `render template: 'errors/404'`. This spec nails the contract so it can't
# silently regress back to a 500:
#   (1) a missing record yields HTTP 404 (NOT 500);
#   (2) it RENDERS the themed errors/404 page (contains "404" + "Go Home"), not a stack trace.
#
# Driven through clients#show with a slug that matches no record — the friendly_id lookup raises
# ActiveRecord::RecordNotFound, which the ApplicationController rescue_from must turn into the 404.
RSpec.describe 'Themed 404 (record not found)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:user) { create(:user, :admin, password: password, password_confirmation: password) }

  before do
    post user_session_path, params: { user: { email: user.email, password: password } }
    get client_path('no-such-client-slug-xyz')
  end

  it 'returns HTTP 404, not a 500' do
    expect(response).to have_http_status(:not_found)
  end

  it 'renders the themed errors/404 page rather than raising (no 500 / stack trace)' do
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('404')
    expect(response.body).to include('Go Home')
  end
end
