# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# Sites surface — program-delivery locations (kind=site agencies), the youth-flavor
# counterpart to Schools. Sites are pure locations (decoupled from attendance/
# academics); a campus is both a school AND a site. Locked to the youth flavor.
RSpec.describe 'Sites surface', type: :request do
  include_context 'youth flavor'
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

  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  it 'renders the Sites index listing the seeded delivery locations' do
    run_task('youth:seed_sites')
    sign_in_as(admin)
    get sites_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Delta HS')
    expect(response.body).to include('Community Site')
  end

  it 'creates a new site as a kind=site agency' do
    sign_in_as(admin)
    expect do
      post sites_path, params: { agency: { name: 'Boys & Girls Club', description: 'Community partner site' } }
    end.to change { Agency.where(kind: 'site').count }.by(1)
    expect(Agency.find_by(name: 'Boys & Girls Club').kind).to eq('site')
  end

  it 'Manage → Agencies excludes sites (no double-listing)' do
    run_task('youth:seed_sites')
    Agency.create!(name: 'Partner Org', kind: 'partner')
    sign_in_as(admin)
    get agencies_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Partner Org')
    expect(response.body).not_to include('Community Site')
  end
end
