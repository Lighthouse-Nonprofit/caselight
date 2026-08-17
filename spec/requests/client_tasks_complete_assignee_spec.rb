# frozen_string_literal: true
require 'rails_helper'

# Tasks could not be completed from the UI (only as a side-effect of ticking them inside a case
# note), so they just went overdue; and the assignee was force-set to the whole caseload on every
# save. This locks: a Complete toggle action, and honoring a chosen assignee subset.
RSpec.describe 'Client tasks: complete + assignee', type: :request do
  include Devise::Test::IntegrationHelpers
  let!(:admin)   { create(:user, roles: 'admin') }
  let!(:worker1) { create(:user, roles: 'case worker') }
  let!(:worker2) { create(:user, roles: 'case worker') }
  let(:domain)   { create(:domain) }
  let(:client)   { create(:client) }

  before do
    client.users = [worker1, worker2] # caseload = both workers
    sign_in admin
  end

  def create_task(params = {})
    post client_tasks_path(client), params: { task: {
      name: 'Call guardian', domain_id: domain.id, completion_date: Date.current.to_s
    }.merge(params) }
  end

  describe 'completing a task' do
    it 'toggles completed via the complete action (and back)' do
      create_task
      task = client.tasks.sole
      expect(task.completed).to be(false)

      patch complete_client_task_path(client, task)
      expect(task.reload.completed).to be(true)

      patch complete_client_task_path(client, task)
      expect(task.reload.completed).to be(false)
    end
  end

  it 'renders the tasks index (complete control + assignee column + completed section)' do
    create_task(user_ids: [worker1.id])
    client.tasks.sole.update_column(:completed, true) # exercise the Completed section branch
    get client_tasks_path(client)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Call guardian')
  end

  describe 'assignee' do
    it 'honors a chosen subset of assignees (does NOT widen to the whole caseload)' do
      create_task(user_ids: [worker1.id])
      expect(client.tasks.sole.reload.user_ids).to contain_exactly(worker1.id)
    end

    it 'defaults to the caseload when no assignee is chosen' do
      create_task
      expect(client.tasks.sole.reload.user_ids).to contain_exactly(worker1.id, worker2.id)
    end
  end
end
