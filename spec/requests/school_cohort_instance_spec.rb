# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# S2/S3/S4 — the school surfaces after the "more than a list" round:
#   * cohort INSTANCE page: every session slot 1..N renders (held or not), tallies
#     per session, roster with completer threshold, unnumbered entries surfaced
#   * report cards are RECORDS: index lists what is on file with an Edit link to
#     the standard tracking form; create lands back on the index
#   * schools link through PROGRAMS both ways (hub Overview + program show)
RSpec.describe 'School programs, report cards, cohort instances', type: :request do
  include_context 'youth flavor'
  CPROPS = { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok' }.freeze
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:school) { Agency.create!(name: 'Delta HS', kind: 'school', description: 'SMJUHSD partner school site') }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let(:girasol) { create(:program_stream, name: 'Girasol') }
  let!(:session_tracking) do
    fields = [
      { 'name' => 's1', 'type' => 'select', 'label' => 'Session Number', 'className' => 'form-control',
        'values' => (1..13).map { |n| { 'label' => n.to_s, 'value' => n.to_s } } },
      { 'name' => 's2', 'type' => 'select', 'label' => 'Attendance', 'required' => true, 'className' => 'form-control',
        'values' => %w[Present Absent Excused].map { |v| { 'label' => v, 'value' => v } } },
      { 'name' => 's3', 'type' => 'textarea', 'label' => 'Session Notes', 'className' => 'form-control' }
    ]
    create(:tracking, name: 'Session Attendance', frequency: 'Weekly', time_of_frequency: 1,
                      program_stream: girasol, fields: fields)
  end
  let(:youth) { create(:client, given_name: 'Coho', family_name: 'Kid', state: 'accepted', users: [worker]) }
  let!(:enrollment) do
    AgencyClient.create!(agency_id: school.id, client_id: youth.id)
    create(:client_enrollment, client: youth, program_stream: girasol,
                               enrollment_date: Time.zone.today - 40, properties: CPROPS)
  end

  def log_session(number, date, attendance)
    create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: session_tracking,
           entry_date: date,
           properties: CPROPS.merge('Session Number' => number.to_s, 'Attendance' => attendance))
  end

  describe 'cohort instance (S4)' do
    it 'lays out all 13 Girasol session slots with tallies and the unheld ones actionable' do
      log_session(1, Time.zone.today - 21, 'Present')
      log_session(2, Time.zone.today - 14, 'Absent')
      sign_in_as(worker)
      get cohort_school_path(school, program_stream_id: girasol.id)
      expect(response).to have_http_status(:ok)
      body = response.body
      expect(body).to include('Girasol')
      # 13 session rows: 2 held (dates rendered) + 11 not-held
      expect(body.scan(I18n.t('schools.cohort.not_held')).size).to eq(11)
      expect(body).to include((Time.zone.today - 21).strftime('%b %d, %Y'))
      expect(body).to include(I18n.t('schools.cohort.take_roll_call'))
      # roster: 1 present of 13, threshold 10 for Girasol -> not a completer
      expect(body).to include('1 / 13')
      expect(body).to include(I18n.t('schools.cohort.threshold', count: 10))
      expect(body).not_to include(I18n.t('schools.cohorts.completer_badge'))
    end

    it 'flags a completer once the threshold is crossed and surfaces unnumbered entries' do
      (1..10).each { |n| log_session(n, Time.zone.today - (30 - n), 'Present') }
      # an imported entry with no session number
      create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: session_tracking,
             entry_date: Time.zone.today - 2, properties: CPROPS.merge('Attendance' => 'Present'))
      sign_in_as(worker)
      get cohort_school_path(school, program_stream_id: girasol.id)
      expect(response.body).to include(I18n.t('schools.cohorts.completer_badge'))
      expect(response.body).to include(I18n.t('schools.cohort.unnumbered', count: 1))
    end

    it 'prefills the roll-call session number from a session link' do
      sign_in_as(worker)
      get roll_call_school_path(school, program_stream_id: girasol.id, session_number: 7)
      expect(response).to have_http_status(:ok)
      # Haml alphabetizes attributes, so tolerate either order
      expect(response.body).to match(/<option[^>]*selected[^>]*>\s*7\s*<\/option>/)
    end
  end

  describe 'report cards as records (S3)' do
    let(:pv) { create(:program_stream, name: '¡Por Vida!') }
    let!(:aeries) do
      fields = Schools::ReportCards::FIELDS.values.each_with_index.map do |label, i|
        { 'name' => "a#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
      end
      create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
    end
    let!(:pv_enrollment) do
      create(:client_enrollment, client: youth, program_stream: pv,
                                 enrollment_date: Time.zone.today - 50, status: 'Active')
    end

    it 'lists report cards on file with an edit link to the tracking form' do
      entry = create(:client_enrollment_tracking, client_enrollment: pv_enrollment, tracking: aeries,
                     entry_date: Time.zone.today - 5,
                     properties: { Schools::ReportCards::FIELDS[:gpa] => '285',
                                   Schools::ReportCards::FIELDS[:attendance] => '93' })
      sign_in_as(worker)
      get report_cards_school_path(school)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Coho Kid')
      expect(response.body).to include('2.85') # x100 rendered for humans
      expect(response.body).to include('93')
      # hrefs carry ?locale=en with alphabetized params — assert stable fragments
      expect(response.body).to include("client_enrollment_trackings/#{entry.id}/edit")
      expect(response.body).to include("tracking_id=#{aeries.id}")
    end

    it 'shows an empty state and keeps the batch grid on its own page' do
      sign_in_as(worker)
      get report_cards_school_path(school)
      expect(response.body).to include(I18n.t('schools.report_cards.none'))
      get new_report_cards_school_path(school)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('schools-entry-grid')
    end

    it 'lands on the index after creating so the new card is visible' do
      sign_in_as(worker)
      post report_cards_school_path(school), params: {
        report_date: Time.zone.today.iso8601,
        report_cards: { youth.id.to_s => { gpa: '310' } }
      }
      expect(response.location).to include("/schools/#{school.id}/report_cards")
      follow_redirect!
      expect(response.body).to include('3.10')
    end
  end

  describe 'schools ↔ programs (S2)' do
    it 'shows hosted programs on the hub and the school on the program page' do
      AgencyProgramStream.create!(agency: school, program_stream: girasol)
      admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
      sign_in_as(admin)

      get school_path(school)
      expect(response.body).to include(I18n.t('schools.show.info_hosted'))
      expect(response.body).to include(program_stream_path(girasol))

      get program_stream_path(girasol)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(school_path(school))
    end

    it 'tells the operator when a school has no programs mapped' do
      admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
      sign_in_as(admin)
      get school_path(school)
      expect(response.body).to include(I18n.t('schools.show.no_hosted'))
    end
  end
end
