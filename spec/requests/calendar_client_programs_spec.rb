# frozen_string_literal: true
require 'rails_helper'

# Owner flip (2026-07-31): the calendar task modal picks the PERSON first, then the
# program — Api::CalendarsController#client_programs feeds the program dropdown. It must
# return ONLY the requested person's ACTIVE program enrollments, and only when that person
# is inside the caller's accessible_by scope: a probed out-of-caseload client_id answers []
# (indistinguishable from a person with no programs — no existence oracle). The modal's
# person list itself is server-rendered from the same accessible_by scope. (Task creation
# is independently re-gated by Client::TasksController#create, so this feed is
# defence-in-depth.)
RSpec.describe 'Api::Calendars#client_programs (calendar task-modal program feed)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password)  { 'SecurePass123!' }
  let!(:housing)  { create(:program_stream, name: 'Housing Stability') }
  let!(:jobs)     { create(:program_stream, name: 'Employment Readiness') }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def enroll(client, prog, status: 'Active')
    create(:client_enrollment, client: client, program_stream: prog, status: status)
  end

  let(:worker)  { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let!(:mine)   { create(:client, state: 'accepted', users: [worker]) }
  let!(:theirs) { create(:client, state: 'accepted') }

  before do
    enroll(mine, housing)
    enroll(mine, jobs, status: 'Exited')
    enroll(theirs, housing)
  end

  it 'requires authentication' do
    get client_programs_api_calendars_path, params: { client_id: mine.id }
    expect(response).to have_http_status(:found)
  end

  context 'as a case worker' do
    before { sign_in_as(worker) }

    it "returns only the person's ACTIVE programs" do
      get client_programs_api_calendars_path, params: { client_id: mine.id }
      expect(response).to have_http_status(:ok)
      names = JSON.parse(response.body).map { |p| p['name'] }
      expect(names).to eq(['Housing Stability'])
      expect(names).not_to include('Employment Readiness') # exited enrollment stays out
    end

    it 'answers [] for an out-of-caseload client_id — no existence oracle' do
      get client_programs_api_calendars_path, params: { client_id: theirs.id }
      expect(response).to have_http_status(:ok)
      expect(JSON.parse(response.body)).to eq([])
    end

    it 'answers [] for an unknown client_id' do
      get client_programs_api_calendars_path, params: { client_id: 999_999 }
      expect(JSON.parse(response.body)).to eq([])
    end
  end

  context 'as an admin' do
    let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
    before { sign_in_as(admin) }

    it "returns any accessible person's active programs" do
      get client_programs_api_calendars_path, params: { client_id: theirs.id }
      expect(JSON.parse(response.body).map { |p| p['name'] }).to eq(['Housing Stability'])
    end
  end

  describe 'the modal itself (calendars#index)' do
    before { sign_in_as(worker) }

    it 'renders the person select live-first and the program select person-dependent' do
      get calendars_path
      expect(response).to have_http_status(:ok)
      body = response.body
      # person select comes first and is enabled; program select waits, disabled.
      # (Haml alphabetizes attributes — extract each whole tag, don't assume order.)
      expect(body).to match(/id=['"]task-client['"][\s\S]*id=['"]task-program['"]/)
      program_tag = body[/<select[^>]*task-program[^>]*>/]
      client_tag  = body[/<select[^>]*task-client[^>]*>/]
      expect(program_tag).to include('disabled')
      expect(client_tag).not_to include('disabled')
      expect(body).to include('Choose a person first')
      # the worker's caseload person is offered as an option (boundary negatives live in the API examples)
      expect(body).to match(/<option value=['"]#{mine.id}['"]>/)
    end
  end
end
