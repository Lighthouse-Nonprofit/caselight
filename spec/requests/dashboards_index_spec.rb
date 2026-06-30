# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'GET /dashboards', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:admin) { create(:user, :admin) }
  before { sign_in admin }

  it 'renders the resettlement dashboard with no chart containers for the JS to bind to' do
    get '/dashboards'
    expect(response).to have_http_status(:ok)
    # HAML renders attributes single-quoted (id='home-index'); match either quote style.
    expect(response.body).to match(/id=['"]home-index['"]/)
    expect(response.body).not_to match(/id=['"]client-by-gender['"]/)
    expect(response.body).not_to match(/id=['"]client-by-status['"]/)
    expect(response.body).not_to match(/id=['"]family-type['"]/)
    expect(response.body).not_to include('data-content-count')
  end
end
