# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# HUB1 — the school hub: header/tabs on every page, ability-scoped chips,
# entry_date-based tiles, latest-entry-only roster glance, cohort cards
# matching the Cohort Completion math, no destructive chrome anywhere.
RSpec.describe 'School hub', type: :request do
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
  let(:pv) { create(:program_stream, name: '¡Por Vida!') }
  let!(:aeries) do
    fields = [Schools::Roster::GPA_LABEL, Schools::Roster::ATTENDANCE_LABEL].each_with_index.map do |label, i|
      { 'name' => "a#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
    end
    create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
  end
  let(:youth) { create(:client, given_name: 'Hub', family_name: 'Kid', state: 'accepted', users: [worker]) }
  let!(:enrollment) do
    AgencyClient.create!(agency_id: school.id, client_id: youth.id)
    create(:client_enrollment, client: youth, program_stream: pv,
                               enrollment_date: Time.zone.today - 60, status: 'Active')
  end

  def add_aeries_entry(date, gpa)
    create(:client_enrollment_tracking, client_enrollment: enrollment, tracking: aeries,
           entry_date: date,
           properties: { Schools::Roster::GPA_LABEL => gpa,
                         Schools::Roster::ATTENDANCE_LABEL => '92' })
  end

  it 'renders header + tabs on all hub pages with ability-scoped chips' do
    other = create(:client, state: 'accepted')
    AgencyClient.create!(agency_id: school.id, client_id: other.id)
    sign_in_as(worker)
    [school_path(school), roster_school_path(school), cohorts_school_path(school)].each do |path|
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__tabs')
      expect(response.body).to include('Delta HS')
    end
    # worker chip counts only their own youth (1, not 2)
    get school_path(school)
    expect(response.body).to include('1 youth linked')
    # no destructive chrome anywhere on the hub
    expect(response.body).not_to include('btn-danger')
  end

  it 'overview tiles count service entries by entry_date; recent activity is scoped and capped' do
    add_aeries_entry(Time.zone.today, '285') # today is always in "this month"
    add_aeries_entry(Time.zone.today.prev_month.beginning_of_month + 2, '250') # outside this month
    sign_in_as(worker)
    get school_path(school)
    expect(response.body).to include('SERVICE ENTRIES THIS MONTH')
    expect(response.body).to match(%r{<h1[^>]*>\s*1\s*</h1>\s*<small[^>]*>\s*SERVICE ENTRIES}m)
    expect(response.body).to include('Academic Check-in (Aeries)') # recent activity row
  end

  it 'roster glances at the LATEST Aeries entry only and flags overdue' do
    add_aeries_entry(Time.zone.today - 100, '250')
    add_aeries_entry(Time.zone.today - 60, '285') # latest, but stale > 45d
    sign_in_as(worker)
    get roster_school_path(school)
    expect(response.body).to include('2.85')
    expect(response.body).not_to include('2.50')
    expect(response.body).to include(I18n.t('schools.roster.overdue', default: 'Check-in overdue'))
    expect(response.body).to include("data-href=\"#{client_path(youth)}")
  end

  it 'cohort cards use the shared Cohorts math with the all-terms fallback note' do
    girasol = create(:program_stream, name: 'Girasol')
    session = create(:tracking, name: 'Session Attendance', frequency: 'Weekly', program_stream: girasol)
    ge = create(:client_enrollment, client: youth, program_stream: girasol,
                                    enrollment_date: Time.zone.today - 30,
                                    properties: { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok',
                                                  'Term' => 'Spring 20' }) # never the current term
    2.times do |i|
      create(:client_enrollment_tracking, client_enrollment: ge, tracking: session,
             entry_date: Time.zone.today - (7 * (i + 1)),
             properties: { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok',
                           'Attendance' => i.zero? ? 'Present' : 'Absent' })
    end
    sign_in_as(worker)
    get cohorts_school_path(school)
    expect(response.body).to include('Girasol')
    expect(response.body).to include(I18n.t('schools.cohorts.all_terms', default: 'All terms'))
    expect(response.body).to include('50%') # 1 Present of 2 logged
  end

  it 'hides the Actions dropdown from a strategic overviewer' do
    school
    overviewer = create(:user, roles: 'strategic overviewer', password: password, password_confirmation: password)
    sign_in_as(overviewer)
    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include(I18n.t('schools.header.actions', default: 'Actions'))
  end
end
