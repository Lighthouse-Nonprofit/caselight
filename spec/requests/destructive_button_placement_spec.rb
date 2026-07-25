# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (D4/R6) — destructive-control placement canary (docs/ui-conventions.md rule 1):
# in the Programs tables' Actions cells, the red Exit control renders AFTER Tracking, at the
# outer edge, outline-styled and gap-separated. One representative surface pins the
# convention; the rest is the documented audit.
RSpec.describe 'Destructive button placement', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }
  let!(:client)  { create(:client, state: 'accepted', users: [admin]) }
  # a tracking makes the program `completed` (set_program_completed), so it lists in the
  # ENROLLED section; tracking_required stays false so the Tracking button renders too
  let!(:program)    { create(:program_stream, name: 'Placement Spec Program') }
  let!(:tracking)   { create(:tracking, program_stream: program) }
  let!(:enrollment) { create(:client_enrollment, client: client, program_stream: program) }
  before { program.save! } # re-fires set_program_completed now that the tracking exists

  it 'renders Exit after Tracking, outline-danger with the gap, on the Programs page' do
    post user_session_path, params: { user: { email: admin.email, password: password } }
    get client_client_enrollments_path(client)
    expect(response).to have_http_status(:ok)
    body = response.body

    exit_pos     = body.index('btn-outline-danger btn-xs btn-width action-gap-start')
    tracking_pos = body.index('btn-primary btn-xs btn-width')
    expect(exit_pos).to be_present
    expect(tracking_pos).to be_present
    expect(tracking_pos).to be < exit_pos
    # solid btn-danger no longer appears in the row-level Actions cells
    expect(body).not_to include('btn btn-danger btn-xs btn-width')
  end
end
