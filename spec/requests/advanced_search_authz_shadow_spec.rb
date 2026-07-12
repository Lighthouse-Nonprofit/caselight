# frozen_string_literal: true
require 'rails_helper'

# AC-3 readiness-report truthfulness (2026-07-12). ClientAdvancedSearchesController#index's
# 5.6 authorization was flag-gated (`authorize! ... if enforce_authorization?`), which left
# @_authorized unset while the flag was OFF — so the AuthorizationShadow detector logged the
# page as a would-403 on the Security Enforcement console permanently, even though every role
# holds :read Client and passes under enforcement (authorization_cutover_enforced_spec). The
# authorize! is now UNCONDITIONAL: behavior-neutral for every role, and the shadow row stops.
# This spec locks both halves so the gated form can't come back.
RSpec.describe 'Advanced search authorization shadow truthfulness', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }

  before do
    AccessLog.delete_all
    sign_in admin
  end

  after { AccessLog.delete_all }

  it 'authorizes unconditionally: no authorization_shadow row is logged while enforcement is OFF' do
    expect(Rails.application.config.x.enforce_authorization).not_to eq(true) # test default: shadow mode

    get '/client_advanced_searches'
    expect(response).to have_http_status(:ok)

    shadow_rows = AccessLog.where(event_type: 'authorization_shadow').select do |ev|
      (ev.metadata || {})['controller'] == 'client_advanced_searches'
    end
    expect(shadow_rows).to be_empty,
      'client_advanced_searches#index logged an authorization_shadow row — the authorize! has ' \
      'regressed to the flag-gated form and the enforcement console will false-positive again'
  end

  it 'remains reachable for a caseload role with the unconditional authorize (flag OFF)' do
    sign_out admin
    worker = create(:user, roles: 'case worker')
    sign_in worker

    get '/client_advanced_searches'
    expect(response).to have_http_status(:ok)
  end
end
