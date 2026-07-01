# frozen_string_literal: true
require 'rails_helper'

# Surface D: prove the icon-only ROW-ACTION controls on an index page render an accessible name in
# the initial server HTML (aria-label) with the glyph hidden. spec/requests is CI-covered. Uses the
# users index because its _actions.html.haml (edit + lock/unlock + remove_link) covers fa_icon
# edit, the state-flipping lock/unlock label, AND remove_link. Do NOT use the live dev admin --
# use factory users (per the frontend-stabilization memory: hammering the real login trips :lockable).
RSpec.describe 'A11y: index row-action accessible names', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let!(:other) { create(:user, roles: 'case worker') }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'names the edit + delete row controls and hides their glyphs' do
    get users_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to match(/aria-label=["']Edit["']/)
    expect(body).to match(/aria-label=["']Delete["']/)
    expect(body).to match(/aria-label=["'](Disable user|Enable user)["']/)
    expect(body).to match(/fa-pencil[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-pencil/)
    expect(body).to match(/fa-trash[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-trash/)
  end

  it 'names the filter-toggle button (icon-only) and hides its icon' do
    get users_path
    body = response.body
    expect(body).to match(/aria-label=["']Toggle search filters["']/)
    expect(body).to match(/fa-filter[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-filter/)
  end
end