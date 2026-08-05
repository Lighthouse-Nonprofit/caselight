# frozen_string_literal: true
require 'rails_helper'

# Access Review "Last Sign In" must be the MOST RECENT sign-in. Devise trackable keeps two
# timestamps with misleading names: current_sign_in_at is the latest sign-in (it survives
# logout), last_sign_in_at is the one BEFORE it. The page used to render last_sign_in_at
# under a "Last Sign In" header, so every user was frozen at their previous (for most, their
# FIRST) login — found by the owner on the production access review 2026-08-04.
RSpec.describe 'Access review sign-in times', type: :request do
  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }

  # A worker whose two sign-ins are far apart, so the wrong column is unmistakable.
  let!(:worker) do
    create(:user, first_name: 'Signin', last_name: 'Fixture').tap do |u|
      u.update_columns(current_sign_in_at: Time.zone.parse('2026-08-01 10:00'),
                       last_sign_in_at:    Time.zone.parse('2026-01-15 09:00'),
                       sign_in_count: 2)
    end
  end

  before do
    post user_session_path, params: { user: { email: admin.email, password: password } }
  end

  it 'shows the most recent sign-in, not the previous one' do
    get access_review_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('2026-08-01 10:00')
    expect(response.body).not_to include('2026-01-15 09:00')
  end

  it 'exports both timestamps under honest CSV headers, most recent first' do
    get access_review_path(format: :csv)
    csv = CSV.parse(response.body, headers: true)
    row = csv.find { |r| r['Email'] == worker.email }

    expect(csv.headers).to include('Last Sign In (most recent)', 'Previous Sign In')
    expect(row['Last Sign In (most recent)']).to start_with('2026-08-01')
    expect(row['Previous Sign In']).to start_with('2026-01-15')
  end

  it 'renders a never-signed-in user with a blank, not an error' do
    never = create(:user, first_name: 'Never', last_name: 'Loggedin')
    never.update_columns(current_sign_in_at: nil, last_sign_in_at: nil, sign_in_count: 0)

    get access_review_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Never Loggedin')
  end
end
