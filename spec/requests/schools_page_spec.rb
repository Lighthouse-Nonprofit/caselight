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
    get school_path(school)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Mine Kid')
    expect(response.body).not_to include('Other Kid')

    get schools_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Santa Maria HS')
  end

  it 'keeps the sidebar entry off the resettlement flavor (test posture)' do
    admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
    sign_in_as(admin)
    get clients_path
    expect(response.body).not_to include("href=\"#{schools_path}") # youth-only structural branch
  end
end
