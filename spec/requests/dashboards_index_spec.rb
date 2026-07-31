# frozen_string_literal: true
require 'rails_helper'

# Data-task batch C4 — role-branched landing dashboard:
#   * admin + strategic overviewer keep the ORG dashboard (index) unchanged
#   * every other role gets the PERSONAL dashboard: own-workload tiles + the 10-day
#     agenda container the JS binds FullCalendar's list view to
RSpec.describe 'GET /dashboards', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  context 'as an admin' do
    let(:admin) { create(:user, :admin) }
    before { sign_in admin }

    it 'renders the org dashboard with no chart containers for the JS to bind to' do
      get '/dashboards'
      expect(response).to have_http_status(:ok)
      # HAML renders attributes single-quoted (id='home-index'); match either quote style.
      expect(response.body).to match(/id=['"]home-index['"]/)
      expect(response.body).not_to match(/id=['"]client-by-gender['"]/)
      expect(response.body).not_to match(/id=['"]client-by-status['"]/)
      expect(response.body).not_to match(/id=['"]family-type['"]/)
      expect(response.body).not_to include('data-content-count')
    end

    it 'does not render the personal agenda' do
      get '/dashboards'
      expect(response.body).not_to match(/id=['"]dashboard-agenda['"]/)
      expect(response.body).not_to match(/id=['"]personal-dashboard['"]/)
    end
  end

  context 'as a strategic overviewer' do
    let(:overviewer) { create(:user, roles: 'strategic overviewer') }
    before { sign_in overviewer }

    it 'renders the org dashboard' do
      get '/dashboards'
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/id=['"]home-index['"]/)
      expect(response.body).not_to match(/id=['"]dashboard-agenda['"]/)
    end
  end

  context 'as a case worker' do
    let(:worker)  { create(:user, roles: 'case worker') }
    let!(:client) { create(:client, state: 'accepted', users: [worker]) }
    let!(:domain) { create(:domain) }
    let!(:overdue) do
      create(:task, client: client, domain: domain, completion_date: Time.zone.today - 2)
    end
    before { sign_in worker }

    it 'renders the personal dashboard: tiles + the 10-day agenda container, no org markup' do
      get '/dashboards'
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/id=['"]personal-dashboard['"]/)
      expect(response.body).to match(/id=['"]dashboard-agenda['"]/)
      expect(response.body).to include('MY OVERDUE TASKS')
      expect(response.body).to include('MY CASELOAD')
      expect(response.body).not_to match(/id=['"]home-index['"]/)
      expect(response.body).not_to include('PROGRAMS OFFERED') # org tile stays org-only
    end

    it 'flags the overdue tile when the worker has overdue work' do
      get '/dashboards'
      expect(response.body).to include('dashboard-flash--alert')
    end
  end
end
