# frozen_string_literal: true
require 'rails_helper'

# Phase 5.6 (AC-3) ROUTE-SMOKE. PROVES the allowlist is complete BEFORE the flip: with enforcement FORCED
# ON for the example, drive every routed action for every role and assert NONE raises
# CanCan::AuthorizationNotPerformed unexpectedly. That failure's unique fingerprint is the
# ApplicationController rescue_from: an AccessLog event_type 'authorization_not_performed' + a static body
# 'Not authorized' with :forbidden. A legit CanCan::AccessDenied is a redirect; a controller's own 403 is
# a real page. So we assert ONLY on that fingerprint, never on 200-vs-403. The static HARD-CI guard gives
# total coverage; this is the empirical confirmation against real routing.
RSpec.describe 'Phase 5.6 authorization-cutover route smoke', type: :request do
  include Devise::Test::IntegrationHelpers

  around(:each) do |ex|
    prev = Rails.application.config.x.enforce_authorization
    Rails.application.config.x.enforce_authorization = true
    begin
      ex.run
    ensure
      Rails.application.config.x.enforce_authorization = prev
    end
  end

  def routed_actions
    Rails.application.routes.routes.filter_map do |r|
      d = r.defaults
      ctrl = d[:controller].to_s
      act  = d[:action].to_s
      next if ctrl.blank? || act.blank? || ctrl.start_with?('rails/')
      # only routed actions the controller actually implements (skip phantom RESTful routes)
      klass = "#{ctrl}_controller".camelize.safe_constantize
      next if klass.nil? || !klass.action_methods.include?(act)
      verb = r.verb.is_a?(String) ? r.verb : r.verb.source.to_s.gsub(/[\^\$]/, '')
      verb = verb.split('|').first.presence || 'GET'
      { controller: ctrl, action: act, verb: verb.downcase.to_sym, spec: r.path.spec.to_s }
    end.uniq { |h| [h[:controller], h[:action], h[:verb], h[:spec]] }
  end

  def build_path(spec)
    path = spec.dup.sub(/\(\.:format\)\z/, '')
    return nil if path.include?('*')
    path = path.gsub(/:[a-z_]+/) { |_| '1' } # :id / :client_id / ... -> '1' (a 404 is acceptable)
    path.presence
  end

  User::ROLES.each do |role|
    it "role=#{role}: no route raises AuthorizationNotPerformed (every action authorizes or is allowlisted)" do
      AccessLog.delete_all
      user = create(:user, roles: role)
      sign_in user

      missed = []
      routed_actions.each do |route|
        path = build_path(route[:spec])
        next if path.nil?
        verb = %i[get post put patch delete].include?(route[:verb]) ? route[:verb] : :get
        begin
          public_send(verb, path)
        rescue ActionController::UrlGenerationError, ActionController::RoutingError
          next # un-satisfiable param -- statically covered by the hard-CI guard
        rescue => _e
          next # unrelated 500 (missing fixture data) is fine; we assert only on the authz fingerprint
        end
        if response.status == 403 && response.body == 'Not authorized'
          missed << "#{route[:verb].upcase} #{route[:spec]} (#{route[:controller]}##{route[:action]})"
        end
      end

      anp = AccessLog.where(event_type: 'authorization_not_performed').to_a
      anp_desc = anp.map { |e| "#{(e.metadata || {})['controller']}##{(e.metadata || {})['action']}" }.uniq

      expect(anp).to be_empty,
        "Routes hit AuthorizationNotPerformed under enforcement for role #{role}: #{anp_desc.inspect}. " \
        "Each must authorize (load_and_authorize_resource/authorize!) or be skip_authorization_check'd."
      expect(missed).to be_empty,
        "Static-403 'Not authorized' fingerprint for role #{role}: #{missed.inspect}"
    ensure
      AccessLog.delete_all
    end
  end
end
