# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D2 — Departments are HIDDEN for the pilot (owner call; possible ERP
# build-out later). Model/table/association stay dormant; these pin the UI absence via
# stable form/filter input NAMES (not the word "Department", which appears elsewhere).
RSpec.describe 'Departments hidden for the pilot (D2)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin) { create(:user, :admin) }
  before { sign_in admin }

  it 'renders the users grid without the department filter or column' do
    get users_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('user_grid[department]')
    expect(response.body).not_to include('user_grid%5Bdepartment%5D')
  end

  it 'renders the user form without a department input' do
    get new_user_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('user[department_id]')
  end

  it 'renders the profile (devise registrations) edit without a department input' do
    get edit_user_registration_path
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('user[department_id]')
  end

  it 'keeps the sidebar free of the departments entry while domains stays' do
    get users_path
    expect(response.body).not_to match(%r{href=["']/departments})
    expect(response.body).to match(%r{href=["']/domains})
  end

  it 'still creates a user without any department params (column dormant, not required)' do
    expect {
      post users_path, params: { user: {
        first_name: 'Pat', last_name: 'Reyes', roles: 'case worker',
        email: 'pat.reyes@example.org', password: 'SecurePass123!',
        password_confirmation: 'SecurePass123!'
      } }
    }.to change(User, :count).by(1)
    expect(User.find_by(email: 'pat.reyes@example.org').department_id).to be_nil
  end
end
