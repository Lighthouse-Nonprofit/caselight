# frozen_string_literal: true
require 'rails_helper'

# Data-task batch (2026-07) — timed tasks land through the existing create path:
# start_time + duration_minutes are OPTIONAL (the case-note/assessment quick-forms stay
# date-only and keep producing all-day tasks); remind_at is gone from the permit list.
RSpec.describe 'Client tasks with times', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:worker)   { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let!(:client)  { create(:client, state: 'accepted', users: [worker]) }
  let!(:domain)  { create(:domain) }

  before { post user_session_path, params: { user: { email: worker.email, password: password } } }

  it 'creates an all-day task without time fields (quick-form shape)' do
    expect do
      post client_tasks_path(client), params: {
        task: { domain_id: domain.id, name: 'Home visit', completion_date: Time.zone.today.to_s }
      }
    end.to change(Task, :count).by(1)

    task = Task.order(:created_at).last
    expect(task).not_to be_timed
    expect(task.start_time).to be_nil
  end

  it 'creates a timed task from start_time + duration' do
    post client_tasks_path(client), params: {
      task: { domain_id: domain.id, name: 'CalFresh appointment',
              completion_date: Time.zone.today.to_s, start_time: '14:30', duration_minutes: 45 }
    }

    task = Task.order(:created_at).last
    expect(task).to be_timed
    expect(task.duration_minutes).to eq(45)
    expect(task.starts_at.strftime('%H:%M')).to eq('14:30')
  end

  it 'silently ignores the retired remind_at param (column dropped)' do
    expect do
      post client_tasks_path(client), params: {
        task: { domain_id: domain.id, name: 'Legacy shape', completion_date: Time.zone.today.to_s,
                remind_at: '2026-08-01' }
      }
    end.to change(Task, :count).by(1)
  end
end
