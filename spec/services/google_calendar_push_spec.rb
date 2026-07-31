# frozen_string_literal: true
require 'rails_helper'
require 'sidekiq/testing'

# Data-task batch C5 — the rebuilt Google push (service + Task hooks). All Google API
# traffic is stubbed at the CalendarService seam; these specs pin:
#   * event SHAPES: timed => EventDateTime(date_time:, app zone); all-day => date: with
#     Google's exclusive end (start + 1 day)
#   * state honesty: insert writes the GoogleTaskEvent row; existing row => update_event;
#     a 404/410 (user deleted the event Google-side) drops stale state and recreates
#   * dormancy: with no GOOGLE_CLIENT_ID/SECRET the Task hooks enqueue NOTHING
RSpec.describe GoogleCalendarPush do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:user)    { create(:user, calendar_integration: true) }
  let!(:client) { create(:client, users: [user]) }
  let!(:domain) { create(:domain, name: 'Housing') }
  let(:service) { instance_double(Google::Apis::CalendarV3::CalendarService) }

  before do
    user.update!(google_refresh_token: 'refresh-token-sentinel')
    allow(Google::Apis::CalendarV3::CalendarService).to receive(:new).and_return(service)
    allow(service).to receive(:authorization=)
    allow_any_instance_of(described_class).to receive(:authorizer).and_return(double('authorizer'))
  end

  def stub_google_env(id, secret)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_ID').and_return(id)
    allow(ENV).to receive(:[]).with('GOOGLE_CLIENT_SECRET').and_return(secret)
  end

  def stub_enabled  = stub_google_env('cid', 'secret')
  def stub_disabled = stub_google_env(nil, nil)

  describe '.enabled?' do
    it 'is false without Google credentials in the environment' do
      stub_disabled
      expect(described_class.enabled?).to be(false)
    end

    it "is false for the literal string 'nil' (.env.example / pilot-box default — the SENDER_EMAIL trap)" do
      stub_google_env('nil', 'nil')
      expect(described_class.enabled?).to be(false)
    end

    it 'is true with both credentials present' do
      stub_enabled
      expect(described_class.enabled?).to be(true)
    end
  end

  describe '#upsert' do
    let(:task) do
      create(:task, client: client, domain: domain, name: 'Home visit',
                    completion_date: Time.zone.today + 1)
    end

    it 'inserts an all-day event (exclusive end) and records the state row' do
      created = double('event', id: 'gcal-event-1')
      expect(service).to receive(:insert_event) do |calendar_id, event|
        expect(calendar_id).to eq('primary')
        expect(event.summary).to eq('Housing - Home visit')
        expect(event.start.date).to eq(task.completion_date.iso8601)
        expect(event.start.date_time).to be_nil
        expect(event.end.date).to eq((task.completion_date + 1).iso8601)
        created
      end

      described_class.new(user).upsert(task)

      row = GoogleTaskEvent.find_by(task_id: task.id, user_id: user.id)
      expect(row.google_event_id).to eq('gcal-event-1')
    end

    it 'pushes a timed task as date_time in the app zone' do
      task.update!(start_time: '14:30', duration_minutes: 45)
      expect(service).to receive(:insert_event) do |_id, event|
        expect(event.start.date_time).to eq(task.starts_at.iso8601)
        expect(event.start.time_zone).to eq(Time.zone.name)
        expect(event.end.date_time).to eq(task.ends_at.iso8601)
        expect(event.start.date).to be_nil
        double('event', id: 'gcal-event-2')
      end

      described_class.new(user).upsert(task)
    end

    it 'updates (not inserts) when a state row already exists' do
      GoogleTaskEvent.create!(task_id: task.id, user_id: user.id, google_event_id: 'gcal-existing')
      expect(service).to receive(:update_event).with('primary', 'gcal-existing', anything)
      expect(service).not_to receive(:insert_event)

      described_class.new(user).upsert(task)
    end

    it 'recreates cleanly when Google says the event is gone (stale state dropped)' do
      GoogleTaskEvent.create!(task_id: task.id, user_id: user.id, google_event_id: 'gcal-stale')
      gone = Google::Apis::ClientError.new('notFound', status_code: 404)
      expect(service).to receive(:update_event).and_raise(gone)
      expect(service).to receive(:insert_event).and_return(double('event', id: 'gcal-fresh'))

      described_class.new(user).upsert(task)

      expect(GoogleTaskEvent.where(task_id: task.id, user_id: user.id).pluck(:google_event_id))
        .to eq(['gcal-fresh'])
    end
  end

  describe '#remove' do
    it 'deletes by event id and tolerates already-gone' do
      expect(service).to receive(:delete_event).with('primary', 'gcal-dead')
        .and_raise(Google::Apis::ClientError.new('notFound', status_code: 404))
      expect { described_class.new(user).remove('gcal-dead') }.not_to raise_error
    end
  end

  describe 'Task hooks (dormancy + fan-out)' do
    around do |example|
      Sidekiq::Testing.fake! { example.run }
    end

    before { GoogleCalendarPushWorker.clear }

    it 'enqueues nothing when the feature is dormant (no env credentials)' do
      stub_disabled
      create(:task, client: client, domain: domain, completion_date: Time.zone.today)
      expect(GoogleCalendarPushWorker.jobs).to be_empty
    end

    it 'enqueues an upsert per opted-in assigned user when enabled' do
      stub_enabled
      task = create(:task, client: client, domain: domain, completion_date: Time.zone.today)
      ops = GoogleCalendarPushWorker.jobs.map { |j| j['args'] }
      expect(ops).to include(['upsert', Apartment::Tenant.current, task.id, user.id, nil])
    end

    it 'skips users without a stored refresh token' do
      stub_enabled
      user.update!(google_refresh_token: nil)
      create(:task, client: client, domain: domain, completion_date: Time.zone.today)
      expect(GoogleCalendarPushWorker.jobs).to be_empty
    end

    it 'enqueues deletes (captured pre-destroy) when a pushed task is destroyed' do
      stub_enabled
      task = create(:task, client: client, domain: domain, completion_date: Time.zone.today)
      GoogleTaskEvent.create!(task_id: task.id, user_id: user.id, google_event_id: 'gcal-bye')
      GoogleCalendarPushWorker.clear

      task.destroy!

      deletes = GoogleCalendarPushWorker.jobs.map { |j| j['args'] }.select { |a| a.first == 'delete' }
      expect(deletes).to eq([['delete', Apartment::Tenant.current, nil, user.id, 'gcal-bye']])
    end
  end
end
