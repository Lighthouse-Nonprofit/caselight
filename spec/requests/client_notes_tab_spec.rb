# frozen_string_literal: true
require 'rails_helper'
require Rails.root.join('spec', 'support', 'youth_flavor')

# OCA 2026-08: the imported casebook notes are ProgressNotes, but the youth client hub only showed the
# (empty) CSI "Case Notes" tab. The youth hub now surfaces a "Notes" tab counting progress notes and
# hides Case Notes; resettlement is unchanged. The progress_notes pages render the shared client hub
# header — which is why ProgressNotesController must `include SensitiveFields` (else 500 -> 409, #305).
RSpec.describe 'Client hub — Notes tab', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin)  { create(:user, roles: 'admin') }
  # state: 'accepted' so the hub header renders its TAB BAR (client-hub__tabs).
  let(:client)  { create(:client, state: 'accepted') }
  before { sign_in admin }

  context 'youth flavor' do
    include_context 'youth flavor'

    it 'shows a Notes tab with the progress-note count and hides Case Notes' do
      create_list(:progress_note, 3, client: client)
      get client_path(client)
      expect(response).to have_http_status(:ok)
      tabs = response.body[/client-hub__tabs.*?<\/ul>/m]
      expect(tabs).to be_present
      expect(tabs).to include(client_progress_notes_path(client)) # Notes tab links to progress notes
      expect(tabs).to include('>3<').or include('> 3 <')           # the count chip
      expect(tabs).not_to include(client_case_notes_path(client))  # Case Notes tab hidden on youth
    end

    it 'renders the progress-notes index with the hub header (guards SensitiveFields include)' do
      create(:progress_note, client: client)
      get client_progress_notes_path(client)
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('client-hub__tabs') # hub header rendered, no 500/409
    end
  end

  context 'resettlement flavor (default)' do
    it 'keeps the Case Notes tab and shows no Notes tab' do
      get client_path(client)
      expect(response).to have_http_status(:ok)
      tabs = response.body[/client-hub__tabs.*?<\/ul>/m]
      expect(tabs).to include(client_case_notes_path(client))
      expect(tabs).not_to include(client_progress_notes_path(client))
    end
  end
end
