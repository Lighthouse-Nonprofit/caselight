# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (C2/R12) — first/last-name sorting for Individuals. The name columns are
# encrypted (SQL ORDER BY sorts ciphertext), so NAME_ORDERS values route through
# ClientGrid#name_sorted_assets (Ruby-side) + Kaminari.paginate_array; every other order
# stays pure datagrid SQL. Contracts:
#   * admin grid + worker cards render in decrypted-name order (asc + desc)
#   * a non-name order (slug) still goes through datagrid untouched
#   * quick_search + name order compose
#   * XLS export with a name order does not 500 (the order is stripped before datagrid)
RSpec.describe 'Client name sorting', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)  { create(:user, :admin, password: password, password_confirmation: password) }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }

  let!(:zoe)   { create(:client, given_name: 'Zoe',   family_name: 'Abbott', state: 'accepted', users: [worker]) }
  let!(:amir)  { create(:client, given_name: 'Amir',  family_name: 'Zidane', state: 'accepted', users: [worker]) }
  let!(:lena)  { create(:client, given_name: 'Lena',  family_name: 'Moreau', state: 'accepted', users: [worker]) }

  def names_in_order(body)
    body.scan(/record-(?:grid__name-link|card__name-link)[^>]*>([^<]+)</).flatten.map(&:strip)
  end

  it 'admin grid: first name A–Z and Z–A' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { order: 'given_name' } }
    expect(response).to have_http_status(:ok)
    expect(names_in_order(response.body)).to eq(['Amir Zidane', 'Lena Moreau', 'Zoe Abbott'])

    get clients_path, params: { client_grid: { order: 'given_name_desc' } }
    expect(names_in_order(response.body)).to eq(['Zoe Abbott', 'Lena Moreau', 'Amir Zidane'])
  end

  it 'admin grid: last name A–Z (the Name-header toggle)' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { order: 'family_name' } }
    expect(names_in_order(response.body)).to eq(['Zoe Abbott', 'Lena Moreau', 'Amir Zidane'])
  end

  it 'worker cards: last name A–Z' do
    sign_in_as(worker)
    get clients_path, params: { client_grid: { order: 'family_name' } }
    expect(response).to have_http_status(:ok)
    expect(names_in_order(response.body)).to eq(['Zoe Abbott', 'Lena Moreau', 'Amir Zidane'])
  end

  it 'a non-name order still routes through datagrid (slug)' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { order: 'slug' } }
    expect(response).to have_http_status(:ok)
  end

  it 'quick_search composes with a name order' do
    sign_in_as(admin)
    get clients_path, params: { client_grid: { quick_search: 'zidane', order: 'given_name' } }
    body = response.body
    expect(body).to include('Amir Zidane')
    expect(body).not_to include('Zoe Abbott')
  end

  it 'XLS export with a name order is stripped, not raised' do
    sign_in_as(admin)
    get clients_path(format: :xls), params: { client_grid: { order: 'family_name' }, type: 'basic_info' }
    expect(response).to have_http_status(:ok)
  end
end
