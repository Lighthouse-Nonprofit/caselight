# frozen_string_literal: true
require 'rails_helper'

# POAM-017f / 12C-1 — the LAST two inline event handlers on browser-served pages were the
# card-grid sort selects' onchange="this.form.submit()" (clients/families index). Under the
# nonce-based CSP (12C-2) inline handlers are blocked, so they moved to the attribute-driven
# shared/auto_submit.js (data-auto-submit + a delegated change handler). Mirrors
# spec/requests/passkey_inline_script_extraction_spec.rb.
RSpec.describe 'Sort-select inline handler extraction (POAM-017f)', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }

  before { sign_in admin }

  it 'renders the clients index sort select with data-auto-submit and no inline onchange' do
    get clients_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/id="client_grid_order"/)
    expect(response.body).to include('data-auto-submit')
    expect(response.body).not_to include('onchange=')
  end

  it 'renders the families index sort select with data-auto-submit and no inline onchange' do
    get families_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to match(/id="family_grid_order"/)
    expect(response.body).to include('data-auto-submit')
    expect(response.body).not_to include('onchange=')
  end

  it 'ships the delegated handler in the bundle' do
    manifest = File.read(Rails.root.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+shared/auto_submit$})
    handler = File.read(Rails.root.join('app/assets/javascripts/shared/auto_submit.js'))
    expect(handler).to include("select[data-auto-submit]")
  end
end
