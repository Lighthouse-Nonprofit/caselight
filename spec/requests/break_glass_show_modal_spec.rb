# frozen_string_literal: true
require 'rails_helper'

# UX rung 5 / round 3 (A1) — the break-glass affordance: emergency_only forms with data render
# as LOCKED rows on the Forms partition page (forms#index — moved there with the Overview
# Forms card) for break-glass-eligible viewers, each opening a declarative BS5 modal that
# embeds the shared break_glass_grants/_form. Contracts:
#   * eligible viewer sees the locked row + a modal carrying the exact grant POST fields
#   * the masked form is NEVER linked to edit from the Forms page (edit has no field gate)
#   * POSTing the grant unlocks the form (title joins the filled table) + the header shows the
#     expiry chip
#   * a strategic_overviewer (never eligible) sees neither locked row nor modal
RSpec.describe 'Break-glass locked rows + modal on the Forms page', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:worker)     { create(:user, roles: 'case worker', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:client) { create(:client, given_name: 'Locky', family_name: 'Cardwell', state: 'accepted', users: [worker]) }

  let!(:emergency_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'ModalSpec Emergency Contact',
           sensitivity: 'emergency_only', fields: [{ 'type' => 'text', 'label' => 'Whereabouts' }])
  end
  let!(:emergency_prop) do
    create(:custom_field_property, custom_field: emergency_cf, custom_formable: client,
           properties: { 'Whereabouts' => 'MODAL_SENTINEL_DO_NOT_LEAK' })
  end

  describe 'eligible viewer (case worker)' do
    before { sign_in_as(worker) }

    it 'renders the locked row and a modal with the exact grant POST fields — and never an edit link' do
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      # locked row affordance
      expect(body).to include('forms__locked')
      expect(body).to include('ModalSpec Emergency Contact')
      expect(body).to include("break-glass-#{emergency_cf.id}")
      # modal embeds the shared form with the exact fields the controller expects
      expect(body).to match(/name="custom_formable_type"[^>]*value="Client"/)
      expect(body).to match(/name="custom_formable_id"[^>]*value="#{client.id}"/)
      expect(body).to match(/name="custom_field_id"[^>]*value="#{emergency_cf.id}"/)
      expect(body).to include('Request emergency access')
      # the sentinel value is NOT on the page, and no edit path for the masked form exists
      expect(body).not_to include('MODAL_SENTINEL_DO_NOT_LEAK')
      expect(body).not_to include(edit_client_custom_field_property_path(client, emergency_prop))
    end

    it 'POSTing the grant unlocks the form and the header shows the expiry chip' do
      post break_glass_grants_path, params: {
        custom_formable_type: 'Client', custom_formable_id: client.id,
        custom_field_id: emergency_cf.id, reason: 'home visit safety concern'
      }
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      # unlocked: the form title now renders as a real row in the filled-forms table with a
      # View-entries link to cfp#index
      expect(body).to include('ModalSpec Emergency Contact')
      expect(CGI.unescapeHTML(body)).to include(client_custom_field_properties_path(client, custom_field_id: emergency_cf.id))
      # expiry chip in the header
      expect(body).to include('client-hub__grant')
      # and the locked card for this form is gone
      expect(body).not_to include("data-bs-target=\"#break-glass-#{emergency_cf.id}\"")
    end
  end

  describe 'strategic_overviewer (never break-glass eligible)' do
    it 'sees neither locked row nor modal nor sentinel on the Forms page' do
      sign_in_as(overviewer)
      get client_forms_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).not_to include('forms__locked')
      expect(body).not_to include("break-glass-#{emergency_cf.id}")
      expect(body).not_to include('ModalSpec Emergency Contact')
      expect(body).not_to include('MODAL_SENTINEL_DO_NOT_LEAK')
    end
  end

  describe 'overview program panes' do
    let!(:program)    { create(:program_stream, name: 'ModalSpec Housing') }
    let!(:enrollment) { create(:client_enrollment, client: client, program_stream: program) }

    it 'renders active enrollments as deep links to the program pane on the Programs tab' do
      sign_in_as(worker)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('ModalSpec Housing')
      # Investor UX round (2026-07): Overview program links deep-link to the Programs tab
      # (?program_stream_id= selects the pane server-side). Regex: the rendered href carries
      # ?locale=en with alphabetized params.
      expect(CGI.unescapeHTML(response.body)).to match(%r{client_enrollments\?[^"]*program_stream_id=#{program.id}})
    end
  end
end
