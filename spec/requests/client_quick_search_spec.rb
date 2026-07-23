# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (C1/R13) — the header quick search end-to-end: clients#index with
# client_grid[quick_search] filters by first OR last name, case-insensitively, for both the
# admin grid and the cards view (one ClientGrid serves both).
RSpec.describe 'Client quick search', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)  { create(:user, :admin, password: password, password_confirmation: password) }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  let!(:maria) { create(:client, given_name: 'Maria', family_name: 'Gonzalez', state: 'accepted', users: [worker]) }
  let!(:bao)   { create(:client, given_name: 'Bao', family_name: 'Tran', state: 'accepted', users: [worker]) }

  it 'admin grid: last name alone, any casing' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { quick_search: 'gonzalez' } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Maria Gonzalez')
    expect(response.body).not_to include('Bao Tran')
  end

  it 'admin grid: "First Last" and the swap both match' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { quick_search: 'Gonzalez Maria' } }
    expect(response.body).to include('Maria Gonzalez')
    expect(response.body).not_to include('Bao Tran')
  end

  it 'cards view (case worker): first name alone' do
    sign_in_as(worker)
    get clients_path, params: { client_grid: { quick_search: 'maria' } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Maria Gonzalez')
    expect(response.body).not_to include('Bao Tran')
  end
end
