# frozen_string_literal: true
# TenantBoundary - defense-in-depth tripwire asserting the Apartment schema in effect
# matches the tenant implied by the request host (FedRAMP AC-3/SC-7, SOC 2 CC6.1).
# The elevator switches the schema before Warden, so under normal operation these always
# agree; this catches a mis-switch / leaked connection / a path that forgot to switch.
# FAIL-SAFE: a false positive would refuse EVERY request for a tenant, so enforcement is
# gated behind config.x.enforce_tenant_boundary (default OFF) - log-only until flipped.
module TenantBoundary
  extend ActiveSupport::Concern

  # Actions that DELIBERATELY operate across tenants (Organization.switch_to loops) and may
  # legitimately leave Apartment::Tenant.current != the request subdomain when this after_action
  # fires. api/clients#compare LEFT this list 2026-07-26 (POAM-AC3-COMPARE: compare is now
  # current-tenant-only). Other mid-request switchers exist (form_builder/custom_fields,
  # program_streams — cross-org form CONFIG reads, never client values) but restore the request
  # tenant before returning, so they need no entry here.
  CROSS_TENANT_ALLOWLIST = {
    'api/custom_fields' => %w[fetch_custom_fields fields].freeze
  }.freeze

  included do
    after_action :assert_tenant_boundary
  end

  private

  def assert_tenant_boundary
    return if cross_tenant_action?

    expected = expected_tenant_from_host
    current  = (Apartment::Tenant.current rescue nil)

    # nil expected = public schema (tenant landing / robots / error pages) - in bounds.
    return if expected.nil?
    return if tenant_matches?(expected, current)

    # Phase 5 capstone: resolve the effective flag ONCE (persisted per-tenant override else config.x boot
    # default; fails SAFE to config.x = OFF) so the logged `enforced` metadata matches the actual gate.
    enforced = EnforcementSetting.enabled?(:enforce_tenant_boundary,
                                           config_default: Rails.application.config.x.enforce_tenant_boundary == true)

    AccessLog.security_event!(
      event_type: 'tenant_mismatch',
      request: request,
      user: (current_user if respond_to?(:current_user)),
      metadata: {
        'expected_tenant' => expected,
        'current_tenant'  => current,
        'controller'      => controller_path,
        'action'          => action_name,
        'enforced'        => enforced
      }
    )

    return unless enforced
    # In an after_action the action has already rendered, so `head :conflict` alone raises
    # AbstractController::DoubleRenderError (silently swallowed by the rescue below), leaving the
    # original 200 in place — the tripwire blanked the body but never actually refused. Reset the
    # performed state (response_body = nil) THEN set the status directly so the refusal sticks (409).
    self.response_body = nil
    self.status = :conflict
  rescue StandardError => e
    Rails.logger.error("[TenantBoundary] #{e.class}: #{e.message}")
    nil
  end

  # Reuse the elevator's OWN parser (verified: reads only `request`, ignores the app arg).
  def expected_tenant_from_host
    Apartment::Elevators::SubdomainWithLocalhost.new(nil).parse_tenant_name(request)
  rescue StandardError
    nil
  end

  def tenant_matches?(expected, current)
    return true if expected == current
    expected.to_s.strip.casecmp?(current.to_s.strip)
  end

  def cross_tenant_action?
    CROSS_TENANT_ALLOWLIST[controller_path]&.include?(action_name)
  end
end
