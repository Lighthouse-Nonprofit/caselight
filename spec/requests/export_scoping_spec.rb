# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U1) — export hygiene contract. The XLS index exports must honor the SAME ability scope
# as their HTML branches (before this unit, users/families/partners f.xls emitted the grid's full
# unscoped assets), and the User export must not carry pin_number (credential-adjacent).
# The load-bearing boundary is users#index.xls: a `manager` can only manage their team + self
# (ability.rb `manager_ids && ARRAY[?]` rule), so an out-of-team user must not appear in their
# export. Family/Partner rules are unconditional for every role that can reach those indexes, so
# their scenarios are admin regressions proving the added scope call doesn't break the export.
RSpec.describe 'XLS export scoping', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  # datagrid 1.4 to_xls emits Excel 97 BIFF via the `spreadsheet` gem — parse it back rather than
  # substring-matching binary.
  def xls_cells(body)
    book = Spreadsheet.open(StringIO.new(body))
    book.worksheets.flat_map { |ws| ws.rows.to_a }.flatten.map(&:to_s)
  end

  describe 'users#index.xls' do
    let!(:manager)  { create(:user, roles: 'manager', email: 'boss@team.test') }
    let!(:teammate) { create(:user, roles: 'case worker', email: 'inteam@team.test', manager_ids: [manager.id], pin_number: 946_137) }
    let!(:outsider) { create(:user, roles: 'case worker', email: 'outofteam@other.test') }

    it 'exports only the manager team + self for a manager' do
      sign_in_as(manager)
      get users_path(format: :xls)
      expect(response).to have_http_status(:ok)

      cells = xls_cells(response.body)
      expect(cells).to include('boss@team.test')
      expect(cells).to include('inteam@team.test')
      expect(cells).not_to include('outofteam@other.test')
    end

    it 'still exports every user for an admin (regression)' do
      admin = create(:user, roles: 'admin', email: 'admin@org.test')
      sign_in_as(admin)
      get users_path(format: :xls)
      expect(response).to have_http_status(:ok)

      cells = xls_cells(response.body)
      expect(cells).to include('boss@team.test', 'inteam@team.test', 'outofteam@other.test', 'admin@org.test')
    end

    it 'does not export pin_number values or the pin_number column' do
      admin = create(:user, roles: 'admin', email: 'admin@org.test')
      sign_in_as(admin)
      get users_path(format: :xls)

      cells = xls_cells(response.body)
      expect(cells).not_to include('946137')
      expect(cells).not_to include(I18n.t('datagrid.columns.users.pin_number'))
    end
  end

  describe 'families#index.xls' do
    let!(:family) { create(:family, name: 'Export Household') }

    it 'still exports for an admin with the ability scope applied (regression)' do
      sign_in_as(create(:user, roles: 'admin'))
      get families_path(format: :xls)
      expect(response).to have_http_status(:ok)
      expect(xls_cells(response.body)).to include('Export Household')
    end
  end

  describe 'partners#index.xls' do
    let!(:partner) { create(:partner, name: 'Export Partner Org') }

    it 'still exports for an admin with the ability scope applied (regression)' do
      sign_in_as(create(:user, roles: 'admin'))
      get partners_path(format: :xls)
      expect(response).to have_http_status(:ok)
      expect(xls_cells(response.body)).to include('Export Partner Org')
    end
  end

  describe 'progress_notes#index.xls' do
    # find_client uses Client.able (able_state 'Accepted') — the fixture must satisfy it.
    let!(:client) { create(:client, able_state: 'Accepted') }
    let!(:note)   { create(:progress_note, client: client, response: 'PN_EXPORT_SENTINEL') }

    it 'still exports the client notes for an admin with the ability scope applied (regression)' do
      sign_in_as(create(:user, roles: 'admin'))
      get client_progress_notes_path(client, format: :xls)
      expect(response).to have_http_status(:ok)
      expect(xls_cells(response.body).join(' ')).to include('PN_EXPORT_SENTINEL')
    end
  end
end
