# frozen_string_literal: true
require 'rails_helper'

# Regression: submitting Advanced Search returned a BLANK page (a 500). Root cause on the server
# side: ClientColumnsVisibility mapped `province_id_` -> :province, a grid column removed
# 2026-07-31; a retained/bookmarked search still carrying `province_id_` pushed that phantom
# column into the Datagrid, which raises on render -> blank 500. (A second, JS-side regression —
# dead iCheck `.checked` selectors sending no column params — is fixed in
# client_advanced_searches/index.js.) This spec locks the server-side hard failure, which had no
# request coverage for the submit case.
RSpec.describe 'Advanced search results render', type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:admin) { create(:user, roles: 'admin') }
  before { sign_in admin }

  def submit(extra = {})
    rules = { condition: 'AND',
              rules: [{ id: 'given_name', field: 'given_name', type: 'string',
                        input: 'text', operator: 'equal', value: 'Zephyrina' }] }.to_json
    get '/client_advanced_searches',
        params: { client_advanced_search: { basic_rules: rules } }.merge(extra)
  end

  it 'renders results (200) when a bookmarked search still carries the removed province column' do
    create(:client, given_name: 'Zephyrina', family_name: 'Testcase', code: 5551)
    # given_name_ = a live column; province_id_ = the stale phantom that used to 500 the page
    submit(given_name_: 'true', province_id_: 'true')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Zephyrina') # grid rendered real rows, not a blank page
  end

  it 'does not crash when ONLY the removed province column is requested (skipped, not pushed)' do
    create(:client, given_name: 'Zephyrina', family_name: 'Testcase', code: 5552)
    submit(province_id_: 'true')
    expect(response).to have_http_status(:ok)
  end

  it 'renders a live column normally (no regression to the happy path)' do
    create(:client, given_name: 'Zephyrina', family_name: 'Testcase', code: 5553)
    submit(given_name_: 'true')
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Zephyrina')
  end
end
