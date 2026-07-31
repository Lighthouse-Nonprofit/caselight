# frozen_string_literal: true
require 'rails_helper'

# Data-task batch (2026-07) — the task-native FullCalendar feed (/api/calendars/find_event):
#   * serves ONLY Task.of_user(current_user) — the personal lens (Task's CanCan rule is
#     deliberately unscoped, so this boundary is the feed's whole security story)
#   * honors FC's visible-range start/end params
#   * explicit shapes: all-day = date-only start + allDay:true + NO end key;
#     timed = offset-less local ISO start/end + allDay:false + durationEditable
#   * bucket classNames drive the calendar colors
RSpec.describe 'Calendar events feed', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:worker)   { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let!(:client)  { create(:client, state: 'accepted', users: [worker]) }
  let!(:domain)  { create(:domain, name: 'Housing') }

  let!(:all_day_today) do
    create(:task, client: client, domain: domain, name: 'Home visit',
                  completion_date: Time.zone.today)
  end
  let!(:timed_tomorrow) do
    create(:task, client: client, domain: domain, name: 'CalFresh appt',
                  completion_date: Time.zone.today + 1, start_time: '14:30', duration_minutes: 45)
  end
  let!(:overdue_task) do
    create(:task, client: client, domain: domain, name: 'Late thing',
                  completion_date: Time.zone.today - 3)
  end
  let!(:out_of_range_task) do
    create(:task, client: client, domain: domain, name: 'Far future',
                  completion_date: Time.zone.today + 90)
  end

  # someone else's caseload — must NEVER appear in this user's feed
  let!(:foreign_client) { create(:client, state: 'accepted') }
  let!(:foreign_task) do
    create(:task, client: foreign_client, domain: domain, name: 'FOREIGN_FEED_SENTINEL',
                  completion_date: Time.zone.today)
  end

  def fetch_feed(from: Time.zone.today - 7, to: Time.zone.today + 14)
    get '/api/calendars/find_event', params: { start: from.iso8601, end: to.iso8601 }
    expect(response).to have_http_status(:ok)
    JSON.parse(response.body)
  end

  before { post user_session_path, params: { user: { email: worker.email, password: password } } }

  it 'serves only the signed-in user\'s tasks, scoped to the visible range' do
    events = fetch_feed
    titles = events.map { |e| e['title'] }

    expect(titles).to include('Housing - Home visit', 'Housing - CalFresh appt', 'Housing - Late thing')
    expect(titles.join).not_to include('FOREIGN_FEED_SENTINEL')
    expect(titles.join).not_to include('Far future') # outside the requested window
  end

  it 'emits the all-day shape: date-only start, allDay true, no end key' do
    event = fetch_feed.find { |e| e['title'].include?('Home visit') }
    expect(event['allDay']).to be(true)
    expect(event['start']).to eq(Time.zone.today.iso8601)
    expect(event).not_to have_key('end')
    expect(event['durationEditable']).to be(false)
  end

  it 'emits the timed shape: offset-less local ISO start/end from wall-clock time + duration' do
    event = fetch_feed.find { |e| e['title'].include?('CalFresh') }
    expect(event['allDay']).to be(false)
    expect(event['start']).to eq("#{(Time.zone.today + 1).iso8601}T14:30:00")
    expect(event['end']).to eq("#{(Time.zone.today + 1).iso8601}T15:15:00")
    expect(event['durationEditable']).to be(true)
  end

  it 'buckets events for coloring and links each into the client task page' do
    events = fetch_feed
    by_title = events.index_by { |e| e['title'] }

    expect(by_title['Housing - Late thing']['classNames']).to eq(['task-overdue'])
    expect(by_title['Housing - Home visit']['classNames']).to eq(['task-today'])
    expect(by_title['Housing - CalFresh appt']['classNames']).to eq(['task-upcoming'])
    expect(by_title['Housing - Home visit']['url']).to include(client_tasks_path(client))
  end
end
