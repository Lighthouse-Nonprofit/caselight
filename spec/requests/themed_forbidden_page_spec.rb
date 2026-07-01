# frozen_string_literal: true
require 'rails_helper'

# Frontend Unit 9 — the sensitivity-gated 403. Phase 5.0/5.3/5.4 denials used to emit a bare
# `render plain: 'Not authorized'`; they now render the themed, value-free errors/403 view. This spec
# nails the CONTRACT that made the plain render safe in the first place, so the theming can't quietly
# regress it:
#   (1) HTTP 403 is preserved (fail-closed status, not a 200/302);
#   (2) it is a RENDER, not a redirect — a redirect_to root_url would loop (root = organizations#index,
#       < ApplicationController, itself subject to the same gate);
#   (3) the body is VALUE-FREE — no masked value, no form title;
#   (4) the body is the THEMED page, not the old plain string.
#
# Driven through custom_field_properties#index as a strategic_overviewer hitting a RESTRICTED form:
# that role is break-glass INELIGIBLE, so the controller takes the static-403 branch (not the
# emergency break-glass prompt) — the deterministic denial path.
RSpec.describe 'Themed 403 (sensitivity denial)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:client)   { create(:client) }

  let!(:restricted_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Unit9 Restricted Health',
           sensitivity: 'restricted', fields: [{ 'type' => 'text', 'label' => 'Health Note' }])
  end
  let!(:res_prop) do
    create(:custom_field_property, custom_field: restricted_cf, custom_formable: client,
           properties: { 'Health Note' => 'RESTRICTED_SENTINEL_VALUE' })
  end

  let(:overviewer) do
    create(:user, :strategic_overviewer, password: password, password_confirmation: password)
  end

  before do
    post user_session_path, params: { user: { email: overviewer.email, password: password } }
    get client_custom_field_properties_path(client, custom_field_id: restricted_cf.id)
  end

  it 'preserves HTTP 403 (fail-closed status)' do
    expect(response).to have_http_status(:forbidden)
  end

  it 'RENDERS rather than redirects (no 3xx / Location — a redirect would loop through root)' do
    expect(response).not_to have_http_status(:redirect)
    expect(response.headers['Location']).to be_nil
  end

  it 'returns the THEMED page, not the old bare "Not authorized" string' do
    expect(response.media_type).to eq('text/html')
    expect(response.body).to include('403')
    expect(response.body).to include('Go Home')
    expect(response.body).not_to eq('Not authorized')
  end

  it 'is VALUE-FREE — neither the masked value nor the form title appears in the body' do
    expect(response.body).not_to include('RESTRICTED_SENTINEL_VALUE')
    expect(response.body).not_to include('Unit9 Restricted Health')
  end
end
