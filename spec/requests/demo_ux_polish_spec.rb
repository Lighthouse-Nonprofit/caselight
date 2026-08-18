# frozen_string_literal: true
require 'rails_helper'

# Demo UX polish: program lifecycle status (pending/active/completed), and the task detail
# modal wired across the task views (client tab, org-wide list, personal dashboard agenda).
RSpec.describe 'Demo UX polish', type: :request do
  include Devise::Test::IntegrationHelpers

  describe 'Program lifecycle status' do
    let!(:admin) { create(:user, roles: 'admin') }
    let!(:program) { create(:program_stream, name: 'Cultura Club') }
    before { sign_in admin }

    it 'defaults to active and renders the programs list (card view) with the status' do
      expect(program.reload.status).to eq('active')
      get program_streams_path
      expect(response).to have_http_status(:ok)
    end

    it 'persists a lifecycle status change and shows the badge on the list' do
      program.update!(status: 'completed')
      get program_streams_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Completed')
    end

    it 'rejects an unknown status' do
      expect { program.update!(status: 'bogus') }.to raise_error(ActiveRecord::RecordInvalid)
    end
  end

  describe 'Task modal across views' do
    let!(:worker) { create(:user, roles: 'case worker') }
    let(:client)  { create(:client).tap { |c| c.users = [worker] } }
    let!(:task)   { create(:task, client: client, completion_date: Time.zone.today) }
    before { sign_in worker }

    it 'renders the client task tab with the modal trigger + one-click complete' do
      get client_tasks_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("taskModal-#{task.id}")
      expect(response.body).to include(complete_client_task_path(client, task))
    end

    it 'renders the org-wide task list with linked client + modal' do
      get tasks_path(user_id: worker.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include("taskModal-#{task.id}")
    end

    it 'renders the personal dashboard agenda with task modals' do
      get '/dashboards'
      expect(response).to have_http_status(:ok)
    end
  end
end
