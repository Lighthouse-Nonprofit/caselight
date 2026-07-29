# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — the consolidated Programs tab (client_enrollments#index):
#   * one BS5 sub-tab per ever-enrolled program (active panes first, then exited)
#   * pane = dates + actions (Add Tracking / Re-enroll / Exit Program) + the report timeline
#     with the OWNER-SPECIFIED column order: Forms | Date | Actions
#   * ?program_stream_id= selects the pane server-side (the Overview deep-link contract)
#   * the Add Program modal lists ONLY never-enrolled complete streams (full ones badge out);
#     exited programs re-enroll from their own pane
#   * the standalone report page 301s to the pane deep link
#   * manage-gated affordances vanish for read-only roles
#   * the hub header renders on the tab AND the deep pages (new/edit) that used to lose it
RSpec.describe 'Consolidated client Programs tab', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, :admin, password: password, password_confirmation: password) }
  let!(:client)  { create(:client, given_name: 'Prue', family_name: 'Gramsworth', state: 'accepted') }

  # Complete streams (the completed flag needs a tracking; save! re-fires set_program_completed)
  let!(:prog_active) { create(:program_stream, name: 'PaneSpec Housing') }
  let!(:tr_active)   { create(:tracking, name: 'Rent Check', program_stream: prog_active) }
  let!(:prog_exited) { create(:program_stream, name: 'PaneSpec Cash Assist') }
  let!(:tr_exited)   { create(:tracking, program_stream: prog_exited) }
  # rules: {} so GET new skips the advanced-search rule gate (age-based, fixture-random)
  let!(:prog_free)   { create(:program_stream, name: 'PaneSpec Employment', rules: {}) }
  let!(:tr_free)     { create(:tracking, program_stream: prog_free) }
  let!(:prog_full)   { create(:program_stream, name: 'PaneSpec Waitlisted', quantity: 0) }
  let!(:tr_full)     { create(:tracking, program_stream: prog_full) }

  let!(:active_enrollment) { create(:client_enrollment, client: client, program_stream: prog_active) }
  let!(:tracking_entry) do
    create(:client_enrollment_tracking, client_enrollment: active_enrollment, tracking: tr_active)
  end
  let!(:exited_enrollment) { create(:client_enrollment, client: client, program_stream: prog_exited) }
  let!(:exit_record) do
    create(:leave_program, client_enrollment: exited_enrollment, program_stream: prog_exited)
  end

  before do
    [prog_active, prog_exited, prog_free, prog_full].each(&:save!) # re-fire set_program_completed
    exited_enrollment.update_columns(status: 'Exited')
    post user_session_path, params: { user: { email: admin.email, password: password } }
  end

  describe 'as admin' do
    it 'renders one pane per ever-enrolled program, active selected by default' do
      get client_client_enrollments_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name') # hub chrome
      expect(body).to include("program-tab-#{prog_active.id}")
      expect(body).to include("program-tab-#{prog_exited.id}")
      # Haml alphabetizes merged class lists — token lookaheads, not a literal class string
      expect(body).to match(/<div(?=[^>]*id="program-pane-#{prog_active.id}")(?=[^>]*\bactive\b)(?=[^>]*\bshow\b)[^>]*>/)
      # the old two-table page is gone
      expect(body).not_to include('Programs List')
      expect(body).not_to include('Number of Place Available')
    end

    it 'orders the timeline columns Forms | Date | Actions and renders the row family' do
      get client_client_enrollments_path(client)
      body = response.body

      expect(body).to match(%r{<th>Forms</th>\s*<th>Date</th>\s*<th>Actions</th>})
      expect(body).to include('Tracking (Rent Check)')
      expect(body).to include('>Enrollment<')
      expect(body).to include('>Exit<') # the exited pane's exit row
      expect(CGI.unescapeHTML(body)).to include(client_client_enrollment_leave_program_path(client, exited_enrollment, exit_record))
    end

    it 'selects the requested pane via ?program_stream_id= and falls back to the first pane' do
      get client_client_enrollments_path(client, program_stream_id: prog_exited.id)
      expect(response.body).to match(/<div(?=[^>]*id="program-pane-#{prog_exited.id}")(?=[^>]*\bactive\b)(?=[^>]*\bshow\b)[^>]*>/)

      get client_client_enrollments_path(client, program_stream_id: 999_999)
      expect(response.body).to match(/<div(?=[^>]*id="program-pane-#{prog_active.id}")(?=[^>]*\bactive\b)(?=[^>]*\bshow\b)[^>]*>/)
    end

    it 'offers the right actions per pane: Add Tracking + Exit on active, Re-enroll on exited' do
      get client_client_enrollments_path(client)
      body = CGI.unescapeHTML(response.body)

      # URL helpers in the body carry ?locale=en with alphabetized params — regex, not literals
      expect(body).to include('Add Tracking')
      expect(body).to match(%r{client_enrollment_trackings/new\?[^"]*tracking_id=#{tr_active.id}})
      expect(body).to include('Exit Program')
      expect(body).to include("client_enrollments/#{active_enrollment.id}/leave_programs/new")
      expect(body).to include('Re-enroll')
    end

    it 'lists only never-enrolled streams in the Add Program modal, badging full ones' do
      get client_client_enrollments_path(client)
      body = CGI.unescapeHTML(response.body)

      # scope to the modal — the panes legitimately carry their own new-enrollment (Re-enroll)
      # links, so whole-body negatives would misfire
      modal = body[/id="add-program-modal".*?modal-footer/m]
      expect(modal).to be_present
      expect(modal).to include('PaneSpec Employment')
      expect(modal).to match(%r{client_enrollments/new\?[^"]*program_stream_id=#{prog_free.id}"})
      expect(modal).to include('PaneSpec Waitlisted')
      expect(modal).to include('This Program is full')
      expect(modal).not_to match(%r{client_enrollments/new\?[^"]*program_stream_id=#{prog_full.id}"})
      # enrolled streams do NOT reappear in the picker (their panes own re-enrollment)
      expect(modal).not_to include('PaneSpec Housing')
      expect(modal).not_to include('PaneSpec Cash Assist')
    end

    it '301s the retired standalone report page to the pane deep link' do
      get report_client_client_enrollments_path(client, program_stream_id: prog_active.id)
      expect(response).to have_http_status(:moved_permanently)
      expect(response).to redirect_to(client_client_enrollments_path(client, program_stream_id: prog_active.id))
    end

    it 'renders the empty state + picker for a never-enrolled client' do
      bare = create(:client, given_name: 'Newly', family_name: 'Arrived', state: 'accepted')
      get client_client_enrollments_path(bare)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Not yet enrolled in a program.')
      expect(response.body).to include('Add Program')
    end

    it 'keeps the hub header on the deep pages that used to lose it' do
      get new_client_client_enrollment_path(client, program_stream_id: prog_free.id)
      expect(response.body).to include('client-hub__name')

      get edit_client_client_enrollment_path(client, active_enrollment, program_stream_id: prog_active.id)
      expect(response.body).to include('client-hub__name')

      get new_client_client_enrollment_client_enrollment_tracking_path(client, active_enrollment, tracking_id: tr_active.id)
      expect(response.body).to include('client-hub__name')

      get new_client_client_enrollment_leave_program_path(client, active_enrollment)
      expect(response.body).to include('client-hub__name')
    end
  end

  describe 'as strategic overviewer (read-only)' do
    let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

    it 'sees the panes but none of the manage affordances' do
      delete destroy_user_session_path
      post user_session_path, params: { user: { email: overviewer.email, password: password } }

      get client_client_enrollments_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include("program-tab-#{prog_active.id}")
      expect(body).not_to include('Add Program')
      expect(body).not_to include('Exit Program')
      expect(body).not_to include('Add Tracking')
      expect(body).not_to include('Re-enroll')
    end
  end
end
