# frozen_string_literal: true
require 'rails_helper'

# Surface D: the persistent INSPINIA chrome (top-navbar hamburger, notification bell, side-menu
# decorative icons, log-out icon) renders on every authenticated page. Assert the icon-only chrome
# controls have accessible names and the decorative nav/log-out icons are aria-hidden. Rendered via
# the dashboards root. If root_path is not the dashboard in this app, point at any authenticated
# page that renders the application layout; the chrome partials are layout-global.
RSpec.describe 'A11y: persistent chrome accessible names', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'names the sidebar-toggle and account/notification controls' do
    get users_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to match(/aria-label=["']Toggle navigation menu["']/)
    expect(body).to match(/aria-label=["']Notifications["']/)
    expect(body).to match(/aria-label=["']Account menu["']/)
  end

  it 'marks decorative chrome glyphs aria-hidden' do
    get users_path
    body = response.body
    # (UX rung 6: the top-bar fa-sign-out icon link is gone — sign-out is a text link in the
    # sidebar profile menu + mobile account dropdown; the account-menu fa-user glyph is the
    # decorative icon there now.)
    expect(body).to match(/fa-user[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-user/)
    expect(body).to match(/fa-bars[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-bars/)
  end

  # C1 — every sidebar rail glyph is decorative (the accessible name is the visually-hidden
  # .nav-label text, which survives mini mode), so each must carry aria-hidden.
  it 'marks every sidebar nav glyph aria-hidden' do
    get users_path
    body = response.body
    %w[fa-th-large fa-users fa-handshake-o fa-address-book-o fa-cogs fa-area-chart
       fa-check-square-o fa-shield].each do |glyph|
      expect(body).to match(/#{glyph}[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*#{glyph}/),
                      "expected the #{glyph} sidebar glyph to be aria-hidden"
    end
  end
end