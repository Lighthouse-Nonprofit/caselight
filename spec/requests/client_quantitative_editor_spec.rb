# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D3 — quantitative types become usable:
#   * the client form renders one select per type (multi only when allow_multiple),
#     with the type description as help text
#   * all selects post into client[quantitative_case_ids][]; a hidden blank clears
#   * values render on the client page (About grid)
#   * the dead /quantitative_cases CRUD routes are gone (changelog #version survives)
RSpec.describe 'Client quantitative editor (D3)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin)   { create(:user, :admin) }
  let!(:client) { create(:client, state: 'accepted', users: [admin]) }

  let!(:single_type) do
    QuantitativeType.create!(name: 'English Proficiency', allow_multiple: false,
                             description: 'Current spoken-English level.')
  end
  let!(:single_a) { single_type.quantitative_cases.create!(value: 'Beginner') }
  let!(:single_b) { single_type.quantitative_cases.create!(value: 'Advanced') }

  let!(:multi_type) { QuantitativeType.create!(name: 'Public Benefits Enrolled', allow_multiple: true) }
  let!(:multi_a) { multi_type.quantitative_cases.create!(value: 'CalFresh (SNAP)') }
  let!(:multi_b) { multi_type.quantitative_cases.create!(value: 'Medi-Cal') }

  before { sign_in admin }

  it 'renders one select per type: single without multiple, multi with it, description as help' do
    get edit_client_path(client)
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/<select[^>]*id="client_quantitative_type_#{single_type.id}"(?![^>]*multiple)/)
    expect(response.body).to match(/<select[^>]*id="client_quantitative_type_#{multi_type.id}"[^>]*multiple/)
    expect(response.body).to include('Current spoken-English level.')
  end

  it 'persists a mixed single + multi assignment through the shared ids array' do
    patch client_path(client), params: { client: { quantitative_case_ids: ['', single_a.id, multi_a.id, multi_b.id] } }
    expect(client.reload.quantitative_case_ids).to contain_exactly(single_a.id, multi_a.id, multi_b.id)
  end

  it 'clears the whole set when only the hidden blank posts' do
    client.quantitative_case_ids = [single_a.id, multi_a.id]
    patch client_path(client), params: { client: { quantitative_case_ids: [''] } }
    expect(client.reload.quantitative_case_ids).to be_empty
  end

  it 'renders assigned values on the client page' do
    client.quantitative_case_ids = [single_b.id]
    get client_path(client)
    expect(response.body).to include('English Proficiency')
    expect(response.body).to include('Advanced')
  end

  it 'rejects a duplicate assignment at the DB (unique pair index)' do
    ClientQuantitativeCase.create!(client: client, quantitative_case: single_a)
    expect {
      ClientQuantitativeCase.create!(client: client, quantitative_case: single_a)
    }.to raise_error(ActiveRecord::RecordNotUnique)
  end

  it 'destroys a type cascade-cleanly and keeps the changelog route only' do
    client.quantitative_case_ids = [multi_a.id]
    expect { multi_type.destroy! }.to change(QuantitativeCase, :count).by(-2)
    expect(client.reload.quantitative_case_ids).to be_empty # join rows cascaded

    # version (changelog) first: an unrouted request consumes warden's one-shot test
    # login (the router 404 bypasses session commit), so probe the dead route LAST
    get "/quantitative_cases/#{single_a.id}/version"
    expect(response).to have_http_status(:ok)
    get '/quantitative_cases' # dead CRUD route — rescued RoutingError renders 404 in test env
    expect(response).to have_http_status(:not_found)
  end
end
