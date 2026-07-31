# frozen_string_literal: true
require 'rails_helper'

# Data-task batch (2026-07) — calendar drag/drop reschedule (PATCH /tasks/:id/reschedule):
#   * personal boundary: Task's CanCan grant is unscoped, so the action re-finds through
#     Task.of_user — a task outside the caller's team must 404, not update
#   * timed drop persists start_time + duration; all-day drop (blank start_time) clears BOTH
#   * resize = same endpoint with a new duration_minutes
RSpec.describe 'Task reschedule (calendar drag/drop)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:worker)   { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let!(:client)  { create(:client, state: 'accepted', users: [worker]) }
  let!(:domain)  { create(:domain, name: 'Housing') }

  let!(:task) do
    create(:task, client: client, domain: domain, name: 'Home visit',
                  completion_date: Time.zone.today + 2, start_time: '10:00', duration_minutes: 30)
  end

  # someone else's caseload — must be untouchable through this endpoint
  let!(:foreign_client) { create(:client, state: 'accepted') }
  let!(:foreign_task) do
    create(:task, client: foreign_client, domain: domain, name: 'FOREIGN_RESCHEDULE_SENTINEL',
                  completion_date: Time.zone.today + 2)
  end

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  it 'requires authentication' do
    patch reschedule_task_path(task), params: { task: { completion_date: Time.zone.today + 5 } }
    expect(response).to have_http_status(:found)
    expect(task.reload.completion_date).to eq(Time.zone.today + 2) # untouched
  end

  context 'signed in as the case worker' do
    before { sign_in_as(worker) }

    it 'moves the date (month-view drop keeps the existing time)' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 7).iso8601,
                              start_time: '10:00', duration_minutes: 30 } }
      expect(response).to have_http_status(:ok)
      task.reload
      expect(task.completion_date).to eq(Time.zone.today + 7)
      expect(task.start_time.strftime('%H:%M')).to eq('10:00')
      expect(task.duration_minutes).to eq(30)
    end

    it 'persists a timed drop into a new slot' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 3).iso8601,
                              start_time: '14:30', duration_minutes: 30 } }
      expect(response).to have_http_status(:ok)
      task.reload
      expect(task.start_time.strftime('%H:%M')).to eq('14:30')
      expect(task.completion_date).to eq(Time.zone.today + 3)
    end

    it 'clears start_time AND duration on an all-day-lane drop (blank start_time)' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 3).iso8601,
                              start_time: '', duration_minutes: '' } }
      expect(response).to have_http_status(:ok)
      task.reload
      expect(task.start_time).to be_nil
      expect(task.duration_minutes).to be_nil
      expect(task.timed?).to be(false)
    end

    it 'clears duration even if the client sent one alongside a blank start_time' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 3).iso8601,
                              start_time: '', duration_minutes: '45' } }
      expect(response).to have_http_status(:ok)
      expect(task.reload.duration_minutes).to be_nil
    end

    it 'persists a resize as a new duration' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 2).iso8601,
                              start_time: '10:00', duration_minutes: 120 } }
      expect(response).to have_http_status(:ok)
      expect(task.reload.duration_minutes).to eq(120)
    end

    it '422s an invalid duration and leaves the task untouched' do
      patch reschedule_task_path(task),
            params: { task: { completion_date: (Time.zone.today + 2).iso8601,
                              start_time: '10:00', duration_minutes: 2000 } }
      expect(response).to have_http_status(:unprocessable_entity)
      expect(task.reload.duration_minutes).to eq(30)
    end

    it "404s a task outside the worker's team (of_user boundary)" do
      patch reschedule_task_path(foreign_task),
            params: { task: { completion_date: (Time.zone.today + 9).iso8601 } }
      expect(response).to have_http_status(:not_found)
      expect(foreign_task.reload.completion_date).to eq(Time.zone.today + 2) # untouched
    end
  end
end
