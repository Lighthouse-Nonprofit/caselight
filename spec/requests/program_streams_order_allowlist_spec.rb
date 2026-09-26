# frozen_string_literal: true
require 'rails_helper'

# 2026-09-26 code pass: ProgramStreamsController sorted the all-organisations tab with
# `p.send(params[:order])` -- any method name in the URL was called on every tenant's programs
# (`?order=destroy` deleted them), and the current tab passed the raw column into ORDER BY, so an
# unknown name 500ed. Both now go through the SORTABLE_COLUMNS allowlist (the three columns the
# sort links actually offer) and anything else falls back to the default name order.
RSpec.describe 'Program streams sort param allowlist', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }
  let!(:zeta)    { create(:program_stream, name: 'Zeta Program') }
  let!(:alpha)   { create(:program_stream, name: 'Alpha Program') }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'never calls a non-column method named in the order param (all_ngo tab)' do
    expect {
      get program_streams_path(tab: 'all_ngo', order: 'destroy', descending: 'true')
    }.not_to change(ProgramStream, :count)

    expect(response).to have_http_status(:ok)
  end

  it 'falls back to the default order for an unknown column on the current tab (no SQL error)' do
    get program_streams_path(tab: 'current', order: 'bogus_column', descending: 'true')

    expect(response).to have_http_status(:ok)
    expect(response.body.index('Alpha Program')).to be < response.body.index('Zeta Program')
  end

  it 'still sorts by an allowed column, descending' do
    get program_streams_path(tab: 'all_ngo', order: 'name', descending: 'true')

    expect(response).to have_http_status(:ok)
    section = response.body[response.body.index('id="ngos-program-streams"')..]
    expect(section.index('Zeta Program')).to be < section.index('Alpha Program')
  end
end
