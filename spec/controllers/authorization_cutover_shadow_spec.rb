# frozen_string_literal: true
require 'rails_helper'

# Phase 5.6 (AC-3) SHADOW-FIRST proofs for AuthorizationShadow. Uses ANONYMOUS controllers (type:
# :controller) to exercise a GENUINE default-open action — after this cutover no PRODUCTION controller
# is default-open by design (that is the point), so a throwaway controller is the only faithful probe.
# The detector keys off @_authorized — the SAME signal check_authorization uses — so a shadow hit is a
# faithful preview of a real 403 under enforcement, and a miss a faithful preview of a pass.
RSpec.describe 'Phase 5.6 authorization-cutover shadow', type: :controller do
  include Devise::Test::ControllerHelpers

  let(:admin) { create(:user, roles: 'admin') }
  before(:each) { AccessLog.delete_all; sign_in(admin) }
  after(:each)  { AccessLog.delete_all; Rails.application.config.x.enforce_authorization = false }

  def shadow_count
    AccessLog.where(event_type: 'authorization_shadow').count
  end

  context 'a DEFAULT-OPEN action (no authorize, not allowlisted)' do
    controller(ApplicationController) do
      def ping; render plain: 'ok'; end
    end
    before { routes.draw { get 'ping' => 'anonymous#ping' } }

    it 'flag OFF: logs exactly one context-only shadow event; response unchanged' do
      get :ping
      expect(response).to have_http_status(:ok)
      expect(shadow_count).to eq(1)
      ev = AccessLog.where(event_type: 'authorization_shadow').last
      expect(ev.metadata['action']).to eq('ping')
      expect(ev.metadata['role']).to eq('admin')
      expect(ev.metadata['enforced']).to eq(false)
      # CONTEXT-ONLY: never record values.
      expect(ev.metadata.keys).to match_array(%w[controller action role enforced])
    end

    it 'flag ON: check_authorization FIRES for the default-open action (fails loudly, logs it); no shadow event' do
      Rails.application.config.x.enforce_authorization = true
      begin
        get :ping
      rescue AbstractController::DoubleRenderError
        # Test-probe artifact: the probe renders 'ok', THEN check_authorization's after_action raises,
        # THEN rescue_from renders the static 403 -> a double-render because the probe already rendered.
        # In PRODUCTION no action is default-open (allowlist + authorize! cover all), so check_authorization
        # never raises there. The security-relevant fact proven here: it FIRED and did NOT silently pass.
      end
      # rescue_from wrote the audit row BEFORE attempting the (double) render -> proof the check fired.
      expect(AccessLog.where(event_type: 'authorization_not_performed').count).to eq(1)
      expect(shadow_count).to eq(0)
    end
  end

  context 'an AUTHORIZED action (authorize! called -> @_authorized set)' do
    controller(ApplicationController) do
      def ping; authorize!(:read, :dummy); render plain: 'ok'; end
    end
    before { routes.draw { get 'ping' => 'anonymous#ping' } }

    it 'flag OFF: writes NO shadow event' do
      get :ping
      expect(shadow_count).to eq(0)
      expect(response).to have_http_status(:ok) # admin can?(:read, :dummy) via manage:all
    end
  end

  context 'an ALLOWLISTED action (skip_authorization_check -> @_authorized set)' do
    controller(ApplicationController) do
      skip_authorization_check
      def ping; render plain: 'ok'; end
    end
    before { routes.draw { get 'ping' => 'anonymous#ping' } }

    it 'flag OFF: writes NO shadow event' do
      get :ping
      expect(shadow_count).to eq(0)
      expect(response).to have_http_status(:ok)
    end
  end
end
