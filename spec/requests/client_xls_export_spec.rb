# frozen_string_literal: true
require 'rails_helper'

# Client XLS export (clients#index.xls) — the richest of the five to_xls exporters and, until now,
# the only one with no spec. It drives the Datagrid#to_xls monkeypatch (config/initializers/
# datagrid.rb: each_with_batches + header/row_for on datagrid 2.0.9) over ClientGrid, decrypting
# Tier 4 given_name/family_name and Tier 2 current_address into worksheet cells, applies the SAME
# accessible_by(current_ability) row-scope the other four exports use, and — only when
# params[:type] == 'basic_info' — appends a per-viewer masked :assessments column via
# domain_score_report, guarded by column_names.any?.
#
# Conventions mirror spec/requests/export_scoping_spec.rb: real Devise POST sign-in, and parse the
# Excel 97 BIFF body back with the `spreadsheet` gem rather than substring-matching binary. The
# tenant ('app') is switched in the global spec_helper before(:each).
RSpec.describe 'Client XLS export (clients#index.xls)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  # datagrid to_xls emits Excel 97 BIFF via the `spreadsheet` gem — parse it back (header + data
  # cells) as an array of strings. (Same helper shape as export_scoping_spec.)
  def xls_cells(body)
    book = Spreadsheet.open(StringIO.new(body))
    book.worksheets.flat_map { |ws| ws.rows.to_a }.flatten.map(&:to_s)
  end

  describe 'encrypted PII round-trip (Tier 4 names, Tier 2 address)' do
    let!(:client) do
      create(:client, state: 'accepted',
                      given_name: 'Amaraexport', family_name: 'Okonkwoexport',
                      current_address: '742 Evergreen Terrace Export')
    end

    it 'decrypts given_name/family_name/current_address into worksheet cells' do
      sign_in_as(create(:user, :admin, password: password, password_confirmation: password))
      get clients_path(format: :xls, given_name_: 'true', family_name_: 'true', current_address_: 'true')
      expect(response).to have_http_status(:ok)

      cells = xls_cells(response.body)
      expect(cells).to include('Amaraexport')                  # Tier 4 given_name decrypted into a cell
      expect(cells).to include('Okonkwoexport')                # Tier 4 family_name decrypted into a cell
      expect(cells).to include('742 Evergreen Terrace Export') # Tier 2 current_address decrypted into a cell
    end
  end

  describe 'row scoping by accessible_by(current_ability)' do
    # case_worker :read is scoped to `case_worker_clients: { user_id: user.id }`; `client.users <<`
    # populates that join, so only the on-caseload client is accessible. Mirrors the users#index.xls
    # manager-team scoping already covered in export_scoping_spec.
    let!(:worker)       { create(:user, :case_worker, password: password, password_confirmation: password) }
    let!(:on_caseload)  { create(:client, state: 'accepted', given_name: 'CaseloadKeeper') }
    let!(:off_caseload) { create(:client, state: 'accepted', given_name: 'CaseloadOutsider') }

    before { on_caseload.users << worker }

    it 'exports only clients on the case worker caseload' do
      sign_in_as(worker)
      get clients_path(format: :xls, given_name_: 'true')
      expect(response).to have_http_status(:ok)

      cells = xls_cells(response.body)
      expect(cells).to include('CaseloadKeeper')        # on-caseload client present
      expect(cells).not_to include('CaseloadOutsider')  # off-caseload client absent (row-scoped out)
    end
  end

  describe 'appended :assessments column masking (domain_score_report / visible_domain_levels)' do
    # type=basic_info makes domain_score_report append a per-viewer :assessments column. Its cell is
    # Assessment#basic_info(visible_levels): visible domains render "Name: score"; hidden ones collapse
    # to an "N restricted hidden" marker. This is the EXPORT masking path — distinct from the already
    # tested HTML CSI chart. given_name_ is selected so column_names.any? is true and the column appends.
    let!(:client)     { create(:client, state: 'accepted', given_name: 'AssessSubject') }
    let!(:assessment) { create(:assessment, client: client) }
    let!(:dg)         { create(:domain_group) }
    let!(:std_domain) { create(:domain, domain_group: dg, name: 'StandardDomainZ',   sensitivity: 'standard') }
    let!(:res_domain) { create(:domain, domain_group: dg, name: 'RestrictedDomainZ', sensitivity: 'restricted') }
    let!(:std_ad)     { create(:assessment_domain, assessment: assessment, domain: std_domain, score: 2) }
    let!(:res_ad)     { create(:assessment_domain, assessment: assessment, domain: res_domain, score: 3) }

    it 'masks the restricted domain for a standard-only viewer (strategic_overviewer)' do
      sign_in_as(create(:user, :strategic_overviewer, password: password, password_confirmation: password))
      get clients_path(format: :xls, type: 'basic_info', given_name_: 'true')
      expect(response).to have_http_status(:ok)

      joined = xls_cells(response.body).join("\n")
      expect(joined).to include('StandardDomainZ')       # non-vacuity: the assessments column IS populated
      expect(joined).not_to include('RestrictedDomainZ') # restricted domain name/score masked on export
      expect(joined).to include('restricted hidden')     # redaction marker emitted in its place
    end

    it 'shows the restricted domain for an admin (all levels visible)' do
      sign_in_as(create(:user, :admin, password: password, password_confirmation: password))
      get clients_path(format: :xls, type: 'basic_info', given_name_: 'true')
      expect(response).to have_http_status(:ok)

      joined = xls_cells(response.body).join("\n")
      expect(joined).to include('StandardDomainZ')
      expect(joined).to include('RestrictedDomainZ')     # admin keeps the restricted score on the export
    end
  end

  describe 'the column_names.any? guard (no display columns selected)' do
    let!(:client) { create(:client, state: 'accepted', given_name: 'GuardSubject') }

    # domain_score_report DEFINES the :assessments column whenever type=basic_info, but only appends
    # it to column_names when a column selection exists (column_names.any?). With NO column_* params
    # the selection stays []; and (verified against datagrid 2.0.9 — ClientGrid declares no mandatory
    # columns) an empty column_names falls back to the FULL default column set. So the guard's real
    # contract is: never let :assessments become the SOLE exported column. Drop the guard and the
    # selection would narrow to [:assessments], collapsing the sheet to an assessments-only column and
    # dropping the client identity columns below.
    it 'keeps the full default column set instead of collapsing to an assessments-only sheet' do
      sign_in_as(create(:user, :admin, password: password, password_confirmation: password))
      get clients_path(format: :xls, type: 'basic_info') # NOTE: no column_* params selected
      expect(response).to have_http_status(:ok)

      cells = xls_cells(response.body)
      expect(cells).to include('Given Name')      # default column header retained (absent if collapsed to assessments-only)
      expect(cells).to include('Current Address') # ...the full default set, not a lone assessments column
      expect(cells).to include('GuardSubject')    # the client's given_name value is still exported
    end
  end
end
