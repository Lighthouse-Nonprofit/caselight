# frozen_string_literal: true
require 'rails_helper'

# Workstream B (SLO4HOME revision): the calendar date-click task modal's "person" dropdown is fed by
# Api::CalendarsController#program_clients. It must return ONLY clients that are (a) ACTIVE-enrolled in
# the requested program AND (b) inside the current user's accessible_by scope. accessible_by is the entire
# authorization boundary -- a case worker must never see (or be able to target) a client outside their own
# caseload, even one enrolled in the same program. (Task creation is independently re-gated by
# Client::TasksController#create via the same accessible_by lookup, so this feed is defence-in-depth.)
RSpec.describe 'Api::Calendars#program_clients (calendar task-modal person feed)', type: :request do
  let(:password) { 'SecurePass123!' }
  let(:program)  { create(:program_stream) }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def enroll(client, prog, status: 'Active')
    create(:client_enrollment, client: client, program_stream: prog, status: status)
  end

  let!(:mine)   { create(:client, given_name: 'Mine',   family_name: 'Caseload') }
  let!(:theirs) { create(:client, given_name: 'Theirs', family_name: 'Elsewhere') }

  before do
    enroll(mine, program)
    enroll(theirs, program)
  end

  context 'as a case worker' do
    let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
    before { mine.users << worker; sign_in_as(worker) }

    it 'returns only the caseload client enrolled in the program (accessible_by boundary)' do
      get program_clients_api_calendars_path(program_id: program.id)
      expect(response).to have_http_status(:ok)
      ids = JSON.parse(response.body).map { |c| c['id'] }
      expect(ids).to include(mine.id)
      expect(ids).not_to include(theirs.id)
    end

    it 'never leaks an out-of-caseload client, even by name' do
      get program_clients_api_calendars_path(program_id: program.id)
      expect(response.body).to include('Mine Caseload')
      expect(response.body).not_to include('Theirs Elsewhere')
    end
  end

  context 'as an admin' do
    let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }
    before { sign_in_as(admin) }

    it 'returns every active-enrolled client in the program' do
      get program_clients_api_calendars_path(program_id: program.id)
      ids = JSON.parse(response.body).map { |c| c['id'] }
      expect(ids).to include(mine.id, theirs.id)
    end

    it 'returns an empty array for a blank / unknown program' do
      get program_clients_api_calendars_path(program_id: 0)
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'excludes non-active enrollments' do
      exited = create(:client, given_name: 'Exited', family_name: 'Gone')
      enroll(exited, program, status: 'Exited')
      get program_clients_api_calendars_path(program_id: program.id)
      ids = JSON.parse(response.body).map { |c| c['id'] }
      expect(ids).not_to include(exited.id)
    end
  end

  it 'requires authentication' do
    get program_clients_api_calendars_path(program_id: program.id)
    expect(response).to have_http_status(:found)
    expect(response.location).to match(/sign_in/)
  end
end
