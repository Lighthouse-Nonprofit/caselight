# frozen_string_literal: true
# TenantBoundary - defense-in-depth tripwire asserting the Apartment schema in effect
# matches the tenant implied by the request host (FedRAMP AC-3/SC-7, SOC 2 CC6.1).
# The elevator switches the schema before Warden, so under normal operation these always
# agree; this catches a mis-switch / leaked connection / a path that forgot to switch.
# FAIL-SAFE: a false positive would refuse EVERY request for a tenant, so enforcement is
# gated behind config.x.enforce_tenant_boundary (default OFF) - log-only until flipped.
module TenantBoundary
  extend ActiveSupport::Concern

  # Actions that DELIBERATELY operate across tenants (Organization.switch_to loops) and so
  # legitimately leave Apartment::Tenant.current != the request subdomain. VERIFIED by grep:
  # only api/clients#compare and api/custom_fields {fetch_custom_fields,fields} switch tenants.
  CROSS_TENANT_ALLOWLIST = {
    'api/clients'       => %w[compare].freeze,
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

    AccessLog.security_event!(
      event_type: 'tenant_mismatch',
      request: request,
      user: (current_user if respond_to?(:current_user)),
      metadata: {
        'expected_tenant' => expected,
        'current_tenant'  => current,
        'controller'      => controller_path,
        'action'          => action_name,
        'enforced'        => !!Rails.application.config.x.enforce_tenant_boundary
      }
    )

    return unless Rails.application.config.x.enforce_tenant_boundary
    self.response_body = nil
    head :conflict
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
