# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Schools batch SCH1 — schools as a first-class surface:
#   * kind=school agencies seeded by youth:seed_schools (idempotent)
#   * roster is ability-scoped (a worker sees only their own caseload's youth)
#   * the sidebar entry is a YOUTH-flavor structural branch (absent on
#     resettlement, which is the test posture — pinned here)
#   * the two new Family forms exist so the household Add-new-form picker is
#     never empty after one fill
RSpec.describe 'Schools surface', type: :request do
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def run_task(name)
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s]) unless Rake::Task.task_defined?(name)
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
    ENV['TENANT'] = Apartment::Tenant.current
    Rake::Task[name].reenable
    saved = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke
  ensure
    $stdout = saved
    ENV.delete('TENANT')
  end

  it 'seed_schools creates the 5 SMJUHSD sites as kind=school, idempotently' do
    2.times { run_task('youth:seed_schools') }
    schools = Agency.where(kind: 'school')
    expect(schools.count).to eq(5)
    expect(schools.pluck(:name)).to include('Santa Maria HS', 'Delta HS')
  end

  it 'seed_taxonomy ships three Family forms (picker never empty after one fill)' do
    run_task('youth:seed_taxonomy')
    family_forms = CustomField.where(entity_type: 'Family')
    expect(family_forms.pluck(:form_title))
      .to contain_exactly('Household & Family Context', 'Family Engagement Log',
                          'Custody & Pickup Authorization')
    expect(family_forms.find_by(form_title: 'Custody & Pickup Authorization').sensitivity)
      .to eq('restricted')
  end

  it 'scopes the roster to the viewer ability (worker sees own caseload only)' do
    run_task('youth:seed_schools')
    school = Agency.find_by(kind: 'school', name: 'Santa Maria HS')
    worker = create(:user, roles: 'case worker', password: password, password_confirmation: password)
    mine = create(:client, given_name: 'Mine', family_name: 'Kid', state: 'accepted', users: [worker])
    other = create(:client, given_name: 'Other', family_name: 'Kid', state: 'accepted')
    [mine, other].each { |c| AgencyClient.create!(agency_id: school.id, client_id: c.id) }

    sign_in_as(worker)
    # HUB1: the roster moved to its own tab page; the overview still 200s.
    get roster_school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Mine Kid')
    expect(response.body).not_to include('Other Kid')

    get school_path(school)
    expect(response).to have_http_status(:ok)

    get schools_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Santa Maria HS')
    # HUB follow-up: the landing page is the record-card grid, not a list
    expect(response.body).to include('record-cards')
    expect(response.body).to include('record-card__avatar')
    expect(response.body).not_to include('reports-tools__item')
  end

  describe 'report-card bulk entry (SCH2)' do
    let(:worker) { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
    let(:pv) { create(:program_stream, name: '¡Por Vida!') }
    let!(:aeries) do
      # real (non-required) Aeries field defs — the factory default fields carry
      # required e-mail/age/description, which would reject report-card rows
      fields = ['GPA (x100, e.g. 275 = 2.75)', 'Credits Earned (cumulative)', 'A-G On Track',
                'School-Day Attendance % (this period)', 'Discipline Incidents (this period)',
                'Concerns / IEP-SST Notes'].each_with_index.map do |label, i|
        { 'name' => "aeries_#{i}", 'type' => 'text', 'label' => label, 'className' => 'form-control' }
      end
      create(:tracking, name: 'Academic Check-in (Aeries)', program_stream: pv, fields: fields)
    end
    let(:school) { run_task('youth:seed_schools'); Agency.find_by(kind: 'school', name: 'Delta HS') }
    let(:youth) { create(:client, given_name: 'Card', family_name: 'Kid', state: 'accepted', users: [worker]) }
    let!(:enrollment) do
      AgencyClient.create!(agency_id: school.id, client_id: youth.id)
      create(:client_enrollment, client: youth, program_stream: pv,
                                 enrollment_date: Time.zone.today - 30, status: 'Active')
    end

    it 'creates one backdated Aeries entry per filled row, skipping blanks' do
      blank_youth = create(:client, state: 'accepted', users: [worker])
      AgencyClient.create!(agency_id: school.id, client_id: blank_youth.id)
      create(:client_enrollment, client: blank_youth, program_stream: pv,
                                 enrollment_date: Time.zone.today - 30, status: 'Active')

      sign_in_as(worker)
      get report_cards_school_path(school)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Card Kid')

      expect do
        post report_cards_school_path(school), params: {
          report_date: (Time.zone.today - 10).iso8601,
          report_cards: {
            youth.id.to_s => { gpa: '285', attendance: '93', ag: 'On track' },
            blank_youth.id.to_s => { gpa: '', attendance: '', ag: '' }
          }
        }
      end.to change(ClientEnrollmentTracking, :count).by(1)

      entry = ClientEnrollmentTracking.order(:created_at).last
      expect(entry.entry_date).to eq(Time.zone.today - 10)
      expect(entry.tracking.name).to eq('Academic Check-in (Aeries)')
      expect(entry.properties['GPA (x100, e.g. 275 = 2.75)']).to eq('285')
      expect(entry.properties).not_to have_key('Credits Earned (cumulative)')
    end

    it 'rejects a bad report date without writing' do
      sign_in_as(worker)
      expect do
        post report_cards_school_path(school), params: { report_date: 'nope',
                                                         report_cards: { youth.id.to_s => { gpa: '300' } } }
      end.not_to change(ClientEnrollmentTracking, :count)
      expect(response.location).to include("/schools/#{school.id}/report_cards") # redirects carry ?locale=en
    end
  end

  it 'link_schools_from_sites bridges School Site values to rosters, idempotently (SCH4)' do
    run_task('youth:seed_schools')
    school = Agency.find_by(kind: 'school', name: 'Pioneer Valley HS')
    # source 1: quantitative selection
    qt = QuantitativeType.create!(name: 'School Site')
    qc = qt.quantitative_cases.create!(value: 'Pioneer Valley HS')
    quant_youth = create(:client, state: 'accepted')
    ClientQuantitativeCase.create!(client_id: quant_youth.id, quantitative_case_id: qc.id)
    # source 2: cohort enrollment field via sidecar
    cohort = create(:program_stream, name: 'Girasol')
    sidecar_youth = create(:client, state: 'accepted')
    create(:client_enrollment, client: sidecar_youth, program_stream: cohort,
                               enrollment_date: Time.zone.today - 10,
                               properties: { 'e-mail' => 't@e.st', 'age' => '3', 'description' => 'ok',
                                             'School Site' => 'Pioneer Valley HS' })

    2.times { run_task('youth:link_schools_from_sites') }
    linked = AgencyClient.where(agency_id: school.id).pluck(:client_id)
    expect(linked).to contain_exactly(quant_youth.id, sidecar_youth.id)
  end

  it 'Manage → Agencies lists partners only — schools never double-list there' do
    run_task('youth:seed_schools')
    partner = Agency.create!(name: 'Partner Org', kind: 'partner')
    admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
    sign_in_as(admin)
    get agencies_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Partner Org')
    expect(response.body).not_to include('Santa Maria HS')
  end

  it 'the school hub Actions offers Edit school details (the agencies modal)' do
    run_task('youth:seed_schools')
    school = Agency.find_by(kind: 'school', name: 'Delta HS')
    admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
    sign_in_as(admin)
    get school_path(school)
    expect(response.body).to include(I18n.t('schools.header.edit_details'))
    expect(response.body).to include("agencyModal-#{school.id}")
  end

  it 'keeps the sidebar entry off the resettlement flavor (test posture)' do
    admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
    sign_in_as(admin)
    get clients_path
    expect(response.body).not_to include("href=\"#{schools_path}") # youth-only structural branch
  end
end
