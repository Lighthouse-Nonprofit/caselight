# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (A2) — the Resettlement Case card folded into the About table. Contracts:
#   * an active case renders as About rows (Resettlement case / Intake date / Case household)
#     and the standalone case card (.overflow-case ibox) is gone
#   * exactly ONE #exit-from-case modal remains (the card used to render a duplicate id)
#   * "Edit Resettlement Case" lives in the header Actions dropdown, gated per-instance
#   * a fully exited case renders the Closed rows
RSpec.describe 'clients#show About case rows', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:admin)      { create(:user, :admin, password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:client) { create(:client, given_name: 'Casey', family_name: 'Rowe', state: 'accepted') }
  let!(:family) { create(:family) }

  describe 'active case' do
    let!(:client_case) { create(:case, case_type: 'FC', client: client, family: family) }

    it 'renders the About rows and drops the standalone card' do
      sign_in_as(admin)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to match(%r{>Case</dt>})
      expect(body).to include('Intake date')
      expect(body).to include(client_case.start_date.strftime('%d %B, %Y'))
      expect(body).to include('Case household')
      expect(body).not_to include('overflow-case')
      # exactly one exit modal (the card used to render a duplicate id)
      expect(body.scan(/id="exit-from-case"/).size).to eq(1)
    end

    it 'offers Edit Resettlement Case in the Actions dropdown to a role that can manage the case' do
      sign_in_as(admin)
      get client_path(client)
      expect(CGI.unescapeHTML(response.body)).to include(edit_client_case_path(client, client_case))
      expect(response.body).to include('Edit Case')
    end

    it 'hides Edit Resettlement Case from a read-only strategic overviewer' do
      sign_in_as(overviewer)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).not_to include('Edit Case')
      # but the About facts are still visible (read access)
      expect(response.body).to match(%r{>Case</dt>})
    end
  end

  describe 'exited case' do
    let!(:client_case) do
      create(:case, case_type: 'FC', client: client, family: family,
             exited: true, exit_date: Date.new(2026, 3, 5), exit_note: 'closed for spec')
    end

    it 'renders the Closed rows' do
      sign_in_as(admin)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to match(%r{>Case</dt>})
      expect(body).to include('Closed')
      expect(body).to include('Case closed on')
      expect(body).to include('05 March, 2026')
    end
  end
end
