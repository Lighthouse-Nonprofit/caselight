# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — the ported create flows. The modern route family
# (client_enrollment_trackings / leave_programs) NEVER had new/create: tracking creation and
# program exit only worked through the legacy client_enrolled_* pages, which retire in P2.
# These examples pin the ported actions end-to-end (they were previously untestable).
RSpec.describe 'Tracking + program-exit creation (modern family)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }
  let!(:client)  { create(:client, given_name: 'Flow', family_name: 'Portsworth', state: 'accepted') }
  let!(:program) { create(:program_stream, name: 'PortSpec Program') }
  let!(:tracking) { create(:tracking, name: 'PortSpec Tracking', program_stream: program) }
  let!(:enrollment) { create(:client_enrollment, client: client, program_stream: program) }

  let(:properties) { { 'e-mail' => 'port@example.com', 'age' => '3', 'description' => 'ported flow' } }

  before do
    program.save! # re-fire set_program_completed now that the tracking exists
    post user_session_path, params: { user: { email: admin.email, password: password } }
  end

  describe 'tracking creation' do
    it 'GET new renders (with the hub header), POST create lands on the program pane' do
      get new_client_client_enrollment_client_enrollment_tracking_path(client, enrollment, tracking_id: tracking.id)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')

      expect do
        post client_client_enrollment_client_enrollment_trackings_path(client, enrollment),
             params: { client_enrollment_tracking: { properties: properties }, tracking_id: tracking.id }
      end.to change(ClientEnrollmentTracking, :count).by(1)

      expect(response).to redirect_to(client_client_enrollments_path(client, program_stream_id: program.id))
      expect(ClientEnrollmentTracking.order(:created_at).last.tracking_id).to eq(tracking.id)
    end
  end

  describe 'program exit (leave_program) creation' do
    it 'GET new renders (with the hub header), POST create exits the enrollment' do
      get new_client_client_enrollment_leave_program_path(client, enrollment)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__name')

      expect do
        post client_client_enrollment_leave_programs_path(client, enrollment),
             params: { leave_program: { exit_date: Date.today.to_s, properties: properties },
                       program_stream_id: program.id }
      end.to change(LeaveProgram, :count).by(1)

      leave = LeaveProgram.order(:created_at).last
      # response.location carries ?locale=en — prefix match on the helper path
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include(client_client_enrollment_leave_program_path(client, enrollment, leave))
      expect(enrollment.reload.status).to eq('Exited')
    end
  end
end
