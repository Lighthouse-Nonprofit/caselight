# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D4 — CA SOGI gender list:
#   * the client form renders the full 8-token picker (one source: Client::GENDER_OPTIONS)
#   * the grid filter matches per token (the old block bucketed every non-'Male' value,
#     including the capitalized column default, as female)
RSpec.describe 'Client gender (CA SOGI list, D4)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin) { create(:user, :admin) }
  before { sign_in admin }

  it 'renders all eight tokens with i18n labels on the client form' do
    get new_client_path
    expect(response).to have_http_status(:ok)
    Client::GENDER_OPTIONS.each do |token|
      expect(response.body).to include(%(value="#{token}")), "missing option #{token}"
    end
    expect(response.body).to include('Non-binary')
    expect(response.body).to include('Declined to state')
  end

  it 'filters the grid per token instead of the old male/everything-else split' do
    nb     = create(:client, state: 'accepted', gender: 'non_binary', users: [admin])
    female = create(:client, state: 'accepted', gender: 'female', users: [admin])

    get clients_path, params: { client_grid: { gender: 'non_binary' } }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("/clients/#{nb.slug}")
    expect(response.body).not_to include("/clients/#{female.slug}")

    get clients_path, params: { client_grid: { gender: 'female' } }
    expect(response.body).to include("/clients/#{female.slug}")
    expect(response.body).not_to include("/clients/#{nb.slug}")
  end

  it 'exposes the SOGI map to both advanced-search field builders' do
    expect(AdvancedSearches::ClientFields.new(user: admin).send(:gender_options).keys.map(&:to_s))
      .to match_array(Client::GENDER_OPTIONS)
    expect(AdvancedSearches::RuleFields.new(user: admin).send(:gender_options).keys.map(&:to_s))
      .to match_array(Client::GENDER_OPTIONS)
  end
end
