# frozen_string_literal: true
require 'rails_helper'

# Phase 5.0 — decision-independent safety rails. Every enforcement flag defaults OFF, so this ships with
# ZERO behavior change. These specs lock that in: the flags are off, the access-review report is
# admin-only, and a normal request is unaffected by the (log-only) tenant-boundary after_action.
# Runs in tenant 'app' (spec_helper switches there).
RSpec.describe 'Phase 5.0 authorization safety rails', type: :request do
  include Devise::Test::IntegrationHelpers
  let(:password) { 'SecurePass123!' }

  describe 'enforcement feature flags default OFF (inert until the org flips them)' do
    it 'enforce_authorization + enforce_tenant_boundary are false' do
      expect(Rails.application.config.x.enforce_authorization).to be(false)
      expect(Rails.application.config.x.enforce_tenant_boundary).to be(false)
    end
  end

  describe 'AC-2(j) access-review report (admin-only)' do
    it 'renders for an admin' do
      admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
      sign_in admin
      get access_review_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Access Review')
    end

    it 'denies a non-admin (case worker) — redirected away, report not shown' do
      worker = create(:user, roles: 'case worker', password: password, password_confirmation: password)
      sign_in worker
      get access_review_path
      expect(response).to have_http_status(:redirect)
    end
  end

  describe 'tenant-boundary after_action is log-only (does not break a normal request)' do
    it 'serves an in-bounds request normally' do
      admin = create(:user, roles: 'admin', password: password, password_confirmation: password)
      sign_in admin
      get access_review_path
      expect(response).to have_http_status(:ok) # the after_action ran without refusing the request
    end
  end
end
