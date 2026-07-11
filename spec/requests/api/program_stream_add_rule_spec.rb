# frozen_string_literal: true
require 'rails_helper'

# POAM-017f defect lock (PR 12A) — the rule-builder filter API renders the
# AdvancedSearches::RuleFields array BARE (no wrapper key). Every JS consumer read
# `response.program_stream_add_rule` (undefined), which is what threw queryBuilder's
# "ConfigError: Missing filters list" on /program_streams/new and stayed latent for want of
# exactly this spec. The consumers now read the array; this locks the contract from the API side.
RSpec.describe 'API: program_stream_add_rule get_fields', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }

  before { sign_in admin }

  it 'returns a BARE JSON array of filter descriptors (no wrapper key)' do
    get '/api/program_stream_add_rule/get_fields'
    expect(response).to have_http_status(:ok)

    body = JSON.parse(response.body)
    expect(body).to be_an(Array), "expected a bare array, got: #{body.class}"
    expect(body).not_to be_empty

    body.each do |descriptor|
      expect(descriptor).to include('id', 'label', 'type', 'operators', 'optgroup')
      expect(descriptor['operators']).to be_an(Array)
    end
  end

  it 'includes the descriptor variants the rule builder renders specially' do
    get '/api/program_stream_add_rule/get_fields'
    body = JSON.parse(response.body)

    droplist = body.find { |d| d['id'] == 'gender' }
    expect(droplist).to be_present
    expect(droplist['input']).to eq('select')
    expect(droplist['values']).to be_present

    datepicker = body.find { |d| d['id'] == 'placement_date' }
    expect(datepicker).to be_present
    expect(datepicker['plugin']).to eq('datepicker')
    expect(datepicker['plugin_config']).to include('format' => 'yyyy-mm-dd')

    integer_field = body.find { |d| d['id'] == 'age' }
    expect(integer_field).to be_present
    expect(integer_field['type']).to eq('integer')
    expect(integer_field['operators']).to include('between')
  end
end
