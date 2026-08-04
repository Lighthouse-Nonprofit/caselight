# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# HUB2 — the entry surfaces:
#   * roll call: no checked defaults, per-curriculum session ranges, exact
#     labels, dedupe skips + flash while other rows save, bad input = 0 writes,
#     foreign/invalid rows ignored, overviewer denied
#   * report cards: placeholders from the LATEST entry, never value=, all-blank
#     POST creates 0 (placeholder-not-submitted pin)
#   * quick entry: single-row POST through the existing endpoint
RSpec.describe 'School entry surfaces', type: :request do
  include_context 'youth flavor'
  RPROPS = { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok' }.freeze
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def seed_schools
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s]) unless Rake::Task.task_defined?('youth:seed_schools')
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    ENV['TENANT'] = Apartment::Tenant.current
    Rake::Task['youth:seed_schools'].reenable
    saved = $stdout
    $stdout = StringIO.new
    Rake::Task['youth:seed_schools'].invoke
  ensure
    $stdout = saved
    ENV.delete('TENANT')
  end

  let(:school) { seed_schools; Agency.find_by(kind: 'school', name: 'Delta HS') }
  let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let(:girasol) { create(:program_stream, name: 'Girasol') }
  let!(:session_tracking) do
    # real seeded field defs — only Attendance is required (the factory default
    # fields would reject every roll-call row)
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
  let(:youth_a) { create(:client, given_name: 'Roll', family_name: 'Kid', state: 'accepted', users: [worker]) }
  let(:youth_b) { create(:client, given_name: 'Call', family_name: 'Kid', state: 'accepted', users: [worker]) }
  let!(:enroll_a) do
    AgencyClient.create!(agency_id: school.id, client_id: youth_a.id)
    create(:client_enrollment, client: youth_a, program_stream: girasol,
                               enrollment_date: Time.zone.today - 30, properties: RPROPS)
  end
  let!(:enroll_b) do
    AgencyClient.create!(agency_id: school.id, client_id: youth_b.id)
    create(:client_enrollment, client: youth_b, program_stream: girasol,
                               enrollment_date: Time.zone.today - 30, properties: RPROPS)
  end

  describe 'roll call' do
    it 'renders a row per cohort youth with NO checked radios and Girasol 13 sessions' do
      sign_in_as(worker)
      get roll_call_school_path(school, program_stream_id: girasol.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Roll Kid', 'Call Kid')
      expect(response.body).not_to include('checked')
      expect(response.body).to include('<option value="13">13</option>')
    end

    it 'creates entries only for set rows with exact labels; dedupe skips but others save' do
      date = Time.zone.today - 1
      # an UNNUMBERED entry on that date (imported/legacy) still blocks — we
      # cannot tell which session it was, so we never risk double-logging
      ClientEnrollmentTracking.create!(client_enrollment_id: enroll_a.id, tracking_id: session_tracking.id,
                                       entry_date: date, properties: { 'Attendance' => 'Present' })
      sign_in_as(worker)
      expect do
        post roll_call_school_path(school), params: {
          program_stream_id: girasol.id, session_date: date.iso8601, session_number: '4',
          roll: { youth_a.id.to_s => { attendance: 'Present' },          # dupe -> skipped
                  youth_b.id.to_s => { attendance: 'Excused', notes: 'sick' },
                  '999999' => { attendance: 'Present' },                 # foreign -> ignored
                  youth_b.id.to_s + '0' => { attendance: 'Nope' } }      # invalid value -> ignored
        }
      end.to change(ClientEnrollmentTracking, :count).by(1)
      entry = ClientEnrollmentTracking.order(:created_at).last
      expect(entry.client_enrollment_id).to eq(enroll_b.id)
      expect(entry.entry_date).to eq(date)
      expect(entry.properties).to eq('Session Number' => '4', 'Attendance' => 'Excused',
                                     'Session Notes' => 'sick')
      follow_redirect!
      expect(response.body).to include(I18n.t('schools.roll_call.skipped', count: 1))
    end

    it 'bad date and out-of-range session write nothing' do
      sign_in_as(worker)
      expect do
        post roll_call_school_path(school), params: { program_stream_id: girasol.id,
                                                      session_date: 'nope', session_number: '4',
                                                      roll: { youth_a.id.to_s => { attendance: 'Present' } } }
        post roll_call_school_path(school), params: { program_stream_id: girasol.id,
                                                      session_date: Time.zone.today.iso8601, session_number: '14',
                                                      roll: { youth_a.id.to_s => { attendance: 'Present' } } }
      end.not_to change(ClientEnrollmentTracking, :count)
    end

    it 'denies a strategic overviewer both verbs' do
      overviewer = create(:user, roles: 'strategic overviewer', password: password, password_confirmation: password)
      sign_in_as(overviewer)
      get roll_call_school_path(school, program_stream_id: girasol.id)
      expect(response).to have_http_status(:redirect)
      expect do
        post roll_call_school_path(school), params: { program_stream_id: girasol.id,
                                                      session_date: Time.zone.today.iso8601, session_number: '1',
                                                      roll: { youth_a.id.to_s => { attendance: 'Present' } } }
      end.not_to change(ClientEnrollmentTracking, :count)
    end
  end

  describe 'report cards prefill + quick entry' do
    let(:pv) { create(:program_stream, name: '¡Por Vida!') }
    let!(:aeries) do
      fields = ['GPA (x100, e.g. 275 = 2.75)', 'School-Day Attendance % (this period)',
                'A-G On Track'].each_with_index.map do |label, i|
        { 'name' => "a#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
      end
      create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
    end
    let!(:pv_enroll) do
      create(:client_enrollment, client: youth_a, program_stream: pv,
                                 enrollment_date: Time.zone.today - 40, status: 'Active')
    end

    before do
      [[60, '250'], [10, '285']].each do |days_ago, gpa|
        create(:client_enrollment_tracking, client_enrollment: pv_enroll, tracking: aeries,
               entry_date: Time.zone.today - days_ago,
               properties: { 'GPA (x100, e.g. 275 = 2.75)' => gpa, 'A-G On Track' => 'On track' })
      end
    end

    it 'shows LATEST-entry placeholders (never value=) and all-blank POST saves 0' do
      sign_in_as(worker)
      get new_report_cards_school_path(school) # S3: the batch grid lives on /new
      expect(response.body).to include('placeholder="285"')
      expect(response.body).not_to include('placeholder="250"')
      expect(response.body).not_to include('value="285"')
      expect(response.body).to include(I18n.t('schools.report_cards.rows_hint'))
      expect(response.body).to include('schools-entry-grid')

      expect do
        post report_cards_school_path(school), params: {
          report_date: Time.zone.today.iso8601,
          report_cards: { youth_a.id.to_s => { gpa: '', credits: '', ag: '' } }
        }
      end.not_to change(ClientEnrollmentTracking, :count)
    end

    it 'roster quick-entry modal posts a single row through the existing endpoint' do
      sign_in_as(worker)
      get roster_school_path(school)
      expect(response.body).to include("quick-entry-#{youth_a.id}")
      expect(response.body).not_to match(/<script(?![^>]*src=)/) # CSP: no INLINE scripts (asset src tags are fine)
      expect do
        post report_cards_school_path(school), params: {
          report_date: (Time.zone.today - 2).iso8601,
          report_cards: { youth_a.id.to_s => { gpa: '300' } }
        }
      end.to change(ClientEnrollmentTracking, :count).by(1)
      entry = ClientEnrollmentTracking.order(:created_at).last
      expect(entry.entry_date).to eq(Time.zone.today - 2)
      expect(entry.properties['GPA (x100, e.g. 275 = 2.75)']).to eq('300')
    end
  end
end
