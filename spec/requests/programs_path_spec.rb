# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — P3 URL cosmetics: the UI has said "Programs" since the round-3
# vocabulary sweep, but the URL still said /program_streams. `resources :program_streams,
# path: 'programs'` renames the path while every helper keeps its name (zero view churn);
# the old index URL 301-redirects for muscle memory. Internal identifiers (ProgramStream,
# /api/program_streams) intentionally unchanged.
RSpec.describe 'Programs URL path', type: :request do
  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'serves the program list at /programs (helper names unchanged)' do
    expect(program_streams_path).to start_with('/programs')
    get program_streams_path
    expect(response).to have_http_status(:ok)
  end

  it 'redirects the old /program_streams URL' do
    get '/program_streams'
    expect(response).to have_http_status(:moved_permanently)
    expect(response.location).to include('/programs')
  end
end
