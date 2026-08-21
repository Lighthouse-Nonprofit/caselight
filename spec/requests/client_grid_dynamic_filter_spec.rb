# frozen_string_literal: true
require 'rails_helper'

# Regression (OCA, 2026-08-19): searching from the Individuals admin filter form 500'd (surfacing as a
# 409 via TenantBoundary on the public-schema error page). Root cause: the form POSTs EVERY datagrid
# :dynamic filter on every search — the CSI `all_domains` + `domain_1a..6b` filters ride along with a
# blank field/value. datagrid 2.x picks a dynamic filter's operator by probing the chosen field's column
# TYPE (`SELECT <field> AS "custom_field" FROM clients LIMIT 1`); a blank field makes that
# `SELECT  AS "custom_field" ...` -> PG::SyntaxError, which datagrid 2.0 re-wraps as an uninitialized
# NameError -> 500. ClientGridOptions#sanitize_dynamic_filters now drops any dynamic filter whose field
# OR value is blank (a no-op filter) before the grid sees it.
RSpec.describe 'Client (Individuals) admin grid — blank dynamic CSI filters', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  # The exact shape the filter form submits: every domain :dynamic filter present but empty.
  def blank_domain_filters
    filters = { all_domains: { field: 'id', operation: '=', value: '' } }
    (1..6).each do |n|
      %w[a b].each { |s| filters["domain_#{n}#{s}"] = { field: '', operation: '=', value: '' } }
    end
    filters
  end

  it 'does not 500 when the admin search carries blank CSI domain dynamic filters' do
    create(:client, given_name: 'Elena', family_name: 'Martinez')
    get clients_path, params: { client_grid: { any_assessments: 'Yes' }.merge(blank_domain_filters) }
    expect(response).to have_http_status(:ok)
  end

  it 'still renders (200) when a fully-specified dynamic filter is present' do
    create(:client, given_name: 'Elena', family_name: 'Martinez')
    get clients_path, params: { client_grid: blank_domain_filters.merge(
      all_domains: { field: 'id', operation: '=', value: '5' }
    ) }
    expect(response).to have_http_status(:ok)
  end

  # Discrimination the fix guarantees, asserted directly on the sanitizer (the crash is a no-op filter
  # reaching datagrid, not anything about rendering): a dynamic filter is kept only when BOTH field and
  # value are present; blank-field, blank-value, and filled-field-but-blank-value are all dropped.
  it 'keeps only fully-specified dynamic filters, drops the no-op ones' do
    controller = ClientsController.new
    raw = ActionController::Parameters.new(
      status:        'accepted',                                        # scalar filter — untouched
      date_of_birth: { from: '2000-01-01', to: '' },                    # range filter (no :field) — untouched
      all_domains:   { field: 'id', operation: '=', value: '5' },       # filled — kept
      domain_1a:     { field: '',   operation: '=', value: '' },        # blank field — dropped
      domain_1b:     { field: 'id', operation: '=', value: '' }         # blank value — dropped
    )
    cleaned = controller.send(:sanitize_dynamic_filters, raw).to_unsafe_h
    expect(cleaned.keys).to contain_exactly('status', 'date_of_birth', 'all_domains')
    expect(cleaned['all_domains']).to eq('field' => 'id', 'operation' => '=', 'value' => '5')
  end
end
