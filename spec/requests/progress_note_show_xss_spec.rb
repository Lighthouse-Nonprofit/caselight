# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'ProgressNote#show narrative sanitization (stored XSS)', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:client)   { create(:client, able_state: 'Accepted') }
  let(:xss)      { %(<img src=x onerror="fetch('/x?c='+document.cookie)"><script>alert(1)</script>) }
  let(:benign)   { '<strong>stable</strong> and <em>improving</em>' }
  let(:note)     { create(:progress_note, client: client, user: admin, response: xss, additional_note: benign) }

  before { sign_in admin }

  it 'strips the attacker payload from the rendered show page' do
    get client_progress_note_path(client, note)
    expect(response).to have_http_status(:ok)
    expect(response.body).not_to include('onerror=')
    expect(response.body).not_to include('<script>alert(1)</script>')
    expect(response.body).not_to include("fetch('/x?c='")
  end

  it 'preserves benign TinyMCE formatting (sanitize, not strip_tags)' do
    get client_progress_note_path(client, note)
    expect(response.body).to include('<strong>stable</strong>')
    expect(response.body).to include('<em>improving</em>')
  end
end
