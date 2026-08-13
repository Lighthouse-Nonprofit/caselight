# frozen_string_literal: true
require 'rails_helper'

# Program Information page — a read-only "what this program is / what it captures"
# view, distinct from #show (the configuration-style field preview). The dashboard's
# "Active enrollments by program" links the program name here, not to the config.
RSpec.describe 'Program information page', type: :request do
  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:program) do
    create(:program_stream, name: 'Mentorship Program',
           description: 'Weekly 1:1 mentoring for youth.',
           rules: { 'rules' => [], 'condition' => 'AND' },
           enrollment: [{ 'name' => 'grade', 'type' => 'select', 'label' => 'Grade', 'values' => [] }])
  end

  before do
    program.trackings.create!(name: 'Mentorship Contact', frequency: 'Monthly',
                              fields: [{ 'name' => 'topic', 'type' => 'text', 'label' => 'Topic' }])
    sign_in_as(admin)
  end

  it 'renders read-only Program Information (name, description, enrollment fields, services)' do
    get info_program_stream_path(program)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Mentorship Program')
    expect(response.body).to include('Weekly 1:1 mentoring for youth.')
    expect(response.body).to include('What this program captures') # info-only heading (absent on #show)
    expect(response.body).to include('Grade')             # enrollment field label, shown as info
    expect(response.body).to include('Mentorship Contact') # service/tracking name
    expect(response.body).to include('Topic')             # tracking field label
  end

  it 'the dashboard links the program name to the info page, not the config show' do
    get dashboards_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include(info_program_stream_path(program))
  end
end
