# frozen_string_literal: true
require 'rails_helper'
require Rails.root.join('spec', 'support', 'youth_flavor')

# Schools/Sites campus UX (2026-08): Sites are now navigable (a show page with the
# programs delivered + youth served + a link to the school twin), Schools are addable,
# and the school<->site "campus" relationship is surfaced both ways. Youth-flavor only.
RSpec.describe 'Schools/Sites campus surfaces', type: :request do
  include_context 'youth flavor'
  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  describe 'adding a school' do
    it 'creates a kind=school agency and, with the campus option, its delivery-site twin' do
      expect do
        post schools_path, params: { agency: { name: 'Righetti Prep', description: 'demo' }, also_site: '1' }
      end.to change { Agency.where(kind: 'school').count }.by(1)
      school = Agency.find_by(name: 'Righetti Prep', kind: 'school')
      expect(school).to be_present
      expect(Agency.where(kind: 'site', name: 'Righetti Prep')).to exist # campus twin
      expect(school.campus?).to be(true)
    end

    it 'adds a school WITHOUT a site twin when the campus option is off' do
      post schools_path, params: { agency: { name: 'Standalone Prep' } }
      expect(Agency.where(kind: 'school', name: 'Standalone Prep')).to exist
      expect(Agency.where(kind: 'site', name: 'Standalone Prep')).not_to exist
    end
  end

  describe 'the Site page' do
    it 'shows the programs delivered there and links the school twin for a campus' do
      program = create(:program_stream, name: '¡Por Vida!')
      site = Agency.create!(name: 'Delta HS', kind: 'site')
      Agency.create!(name: 'Delta HS', kind: 'school') # makes Delta HS a campus
      AgencyProgramStream.create!(agency: site, program_stream: program)

      get site_path(site)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Programs delivered here')
      expect(response.body).to include('¡Por Vida!')
      expect(response.body).to include(school_path(Agency.find_by(name: 'Delta HS', kind: 'school')))
    end

    it 'labels a site with no school twin as a community location' do
      site = Agency.create!(name: 'Boys & Girls Club', kind: 'site')
      get site_path(site)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Community delivery location')
    end
  end

  describe 'the Sites index' do
    it 'links each site to its page and distinguishes campuses from community sites' do
      Agency.create!(name: 'Delta HS', kind: 'site')
      Agency.create!(name: 'Delta HS', kind: 'school')
      Agency.create!(name: 'Community Site', kind: 'site')
      get sites_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(site_path(Agency.find_by(name: 'Delta HS', kind: 'site')))
      expect(response.body).to include('Campus')
      expect(response.body).to include('Community site')
    end
  end

  describe 'the Schools index' do
    it 'offers an Add-school control and badges a campus school with its site link' do
      Agency.create!(name: 'Delta HS', kind: 'school')
      Agency.create!(name: 'Delta HS', kind: 'site')
      get schools_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Add school')
      expect(response.body).to include(site_path(Agency.find_by(name: 'Delta HS', kind: 'site')))
    end
  end
end
