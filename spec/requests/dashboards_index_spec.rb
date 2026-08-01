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

    it 'renders the exact base labels with no flavor overlay active (Y1 byte-identical pin)' do
      # The Y1 t()-conversion of the org dashboard must not change a character when
      # FLAVOR is unset (test/CI posture = resettlement, whose overlay is minimal).
      get '/dashboards'
      %w[HOUSEHOLDS INDIVIDUALS PROGRAMS\ OFFERED OVERDUE\ TASKS].each do |label|
        expect(response.body).to include(label)
      end
      expect(response.body).to include('ACTIVE PROGRAM ENROLLMENTS')
      expect(response.body).to include('TASKS DUE TODAY')
      expect(response.body).to include('NEW INDIVIDUALS THIS MONTH')
      expect(response.body).to include('CHECK-INS THIS MONTH')
      expect(response.body).to include('Active enrollments by program')
      expect(response.body).to include('Recent program activity')
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
    let!(:timed_today) do
      create(:task, client: client, domain: domain, name: 'Morning check-in',
                    completion_date: Time.zone.today, start_time: '09:30', duration_minutes: 60)
    end
    let!(:all_day_tomorrow) do
      create(:task, client: client, domain: domain, name: 'Submit paperwork',
                    completion_date: Time.zone.today + 1)
    end
    before { sign_in worker }

    it 'renders the personal dashboard: tiles + the server-rendered 7-day schedule, no org markup' do
      get '/dashboards'
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(/id=['"]personal-dashboard['"]/)
      expect(response.body).to include('MY OVERDUE TASKS')
      expect(response.body).to include('MY CASELOAD')
      expect(response.body).not_to match(/id=['"]home-index['"]/)
      expect(response.body).not_to include('PROGRAMS OFFERED') # org tile stays org-only
      expect(response.body).not_to include('dashboard-agenda') # the FC list view is gone
    end

    it 'renders one row per day — populated days with tasks, empty days with the structured none-state' do
      get '/dashboards'
      expect(response.body.scan('agenda-day__rail').size).to eq(7)
      expect(response.body).to include('agenda-day--today')
      # timed task: clock time + name; all-day task: the All day chip
      expect(response.body).to include('9:30 AM')
      expect(response.body).to include('Morning check-in')
      expect(response.body).to include('All day')
      expect(response.body).to include('Submit paperwork')
      # 7 days minus the two populated ones still render, as calm empty rows
      expect(response.body.scan('Nothing scheduled').size).to eq(5)
      # the overdue task (yesterday) belongs to the tile, not the week schedule
      expect(response.body.scan('agenda-task').size).to be >= 2
    end

    it 'flags the overdue tile when the worker has overdue work' do
      get '/dashboards'
      expect(response.body).to include('dashboard-flash--alert')
    end
  end
end
