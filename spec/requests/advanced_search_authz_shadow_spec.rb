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

  describe 'shadow-review windowing (the other half of report truthfulness)' do
    # Historical shadow rows are append-only audit — they cannot be deleted when a finding is
    # fixed, so the READINESS surfaces must window to recent usage or they report fixed
    # findings forever (exactly how this defect was discovered on the enforcement console).
    def shadow_row!(controller_name, created_at)
      AccessLog.new(
        event_type: 'authorization_shadow',
        user_email: admin.email,
        metadata: { 'controller' => controller_name, 'action' => 'index',
                    'role' => 'admin', 'enforced' => false },
        created_at: created_at
      ).save!
    end

    it 'the enforcement console shows only rows inside AccessLog::SHADOW_REVIEW_WINDOW' do
      shadow_row!('stale_fixed_thing', (AccessLog::SHADOW_REVIEW_WINDOW + 1.day).ago)
      shadow_row!('fresh_live_thing',  1.hour.ago)

      get '/admin/enforcement_settings'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('fresh_live_thing')
      expect(response.body).not_to include('stale_fixed_thing'),
        'a shadow row older than SHADOW_REVIEW_WINDOW is still rendered — the readiness ' \
        'report has regressed to last-200-ever and will report fixed findings forever'
    end

    it 'the access review report applies the same window' do
      shadow_row!('stale_fixed_thing', (AccessLog::SHADOW_REVIEW_WINDOW + 1.day).ago)
      shadow_row!('fresh_live_thing',  1.hour.ago)

      get '/admin/access_review'
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('fresh_live_thing')
      expect(response.body).not_to include('stale_fixed_thing')
    end
  end
end
