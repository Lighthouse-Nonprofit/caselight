# frozen_string_literal: true
require 'rails_helper'

# Regression (OCA production, 2026-09-24): /families 500ed twice with
#   NoMethodError: undefined method 'begin' for an instance of Float
# datagrid 2.0.9's RangedFilter#parse_values stores a plain String scalar AS-IS (only Hash/Array/
# Range values become a Range), and the filter FORM then calls `value.begin` on it. Any hand-edited,
# bookmarked or scanner URL that hands a `range: true` filter a single value -- e.g.
# ?family_grid[household_income]=5 -- therefore crashed the whole index page (a 409 on the tenanted
# boxes, because the error page renders in the public schema). ApplicationController#
# coerce_range_filter_params now turns a scalar into datagrid's own single-point range [v, v] and
# clamps arrays longer than two (which datagrid rejects with ArgumentError). Every grid with
# range filters is covered; this spec walks one URL per grid.
RSpec.describe 'Grid range filters given a scalar param', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'families: a scalar float range value renders the grid (and the range form) instead of 500ing' do
    create(:family, household_income: 5.0)

    get families_path(family_grid: { household_income: '5' })

    expect(response).to have_http_status(:ok)
    expect(response.body).to include('family_grid[household_income][from]')
  end

  it 'families: a scalar date range value renders' do
    get families_path(family_grid: { contract_date: '2026-01-01' })
    expect(response).to have_http_status(:ok)
  end

  it 'families: an over-long range array is clamped instead of raising' do
    get families_path(family_grid: { household_income: %w[1 2 3] })
    expect(response).to have_http_status(:ok)
  end

  it 'families: a stale order column still degrades to unordered (the pre-existing guard)' do
    get families_path(family_grid: { order: 'province', household_income: '5' })
    expect(response).to have_http_status(:ok)
  end

  it 'users: a scalar date range value renders' do
    get users_path(user_grid: { date_of_birth: '1990-01-01' })
    expect(response).to have_http_status(:ok)
  end

  it 'partners: a scalar date range value renders' do
    get partners_path(partner_grid: { start_date: '2020-01-01' })
    expect(response).to have_http_status(:ok)
  end

  it 'clients: a scalar float range value renders' do
    get clients_path(client_grid: { age: '5' })
    expect(response).to have_http_status(:ok)
  end

  it 'clients: a proper two-ended range is passed through untouched' do
    get clients_path(client_grid: { age: { from: '1', to: '9' } })
    expect(response).to have_http_status(:ok)
  end
end
