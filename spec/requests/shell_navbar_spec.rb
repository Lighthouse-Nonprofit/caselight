# frozen_string_literal: true
require 'rails_helper'

# UX rung 6 — top-navbar dedupe contract: sign-out renders exactly twice (the sidebar profile
# menu + the small-screen account dropdown), the desktop top-bar text link is gone, and the
# calendar link is a proper %li child of the top-links list (it was a bare <a> that broke the
# bar's flex row on small screens).
RSpec.describe 'Shell navbar', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:user, :admin) }
  before { sign_in admin }

  it 'renders sign-out exactly twice: sidebar profile menu + mobile account dropdown' do
    get '/dashboards'
    expect(response).to have_http_status(:ok)
    expect(response.body.scan(%r{href=['"][^'"]*/users/sign_out[^'"]*['"]}).size).to eq(2)
    # the mobile account dropdown carries it (the d-sm-none li)
    expect(response.body).to include('account-setting')
  end

  it 'wraps the calendar link in an li inside navbar-top-links' do
    get '/dashboards'
    expect(response.body).to match(%r{<li>\s*<a[^>]*aria-label=['"]Calendar['"]}m)
  end

  it 'renders the sidebar toggle as a quiet link, not a primary button' do
    get '/dashboards'
    expect(response.body).to match(/navbar-minimalize[^>]*cl-topnav__toggle|cl-topnav__toggle[^>]*navbar-minimalize/)
    expect(response.body).not_to match(/navbar-minimalize[^>]*btn-primary/)
  end
end
