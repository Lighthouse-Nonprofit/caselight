module Api
  class ClientsController < AdminController
    include SensitiveFields # Phase 5.3 — per-tenant visible_custom_field_ids + visible_domain_levels (record-less => break_glass: [])

    # Phase 5.6 (AC-3) allowlist (only: [:compare]): cross-org dedup JSON that authorizes DIFFERENTLY --
    # it returns org-wide identity matches but applies Phase-5.3 sensitive-field/domain MASKING via
    # ClientSerializer (break_glass: []) instead of a record-level CanCan authorize. RESIDUAL
    # (POAM-AC3-COMPARE): a signed-in user can confirm a basic-identity match exists in any tenant
    # regardless of caseload; masking limits this to non-sensitive identity fields. Also on the
    # TenantBoundary cross-tenant allowlist (orthogonal to authz).
    skip_authorization_check only: [:compare]

    def compare
      render json: { clients: find_client_in_organization }
    end

    private

    def find_client_in_organization
      serialized = []
      Organization.without_demo.each do |org|
        Organization.switch_to(org.short_name)
        clients = find_client_by(params)
        next unless clients.any?
        set_organization_to_client(clients, org.full_name)
        # Per-tenant recompute (caseload/role/sensitivity are tenant-local).
        @visible_custom_field_ids = nil
        @visible_domain_levels    = nil
        visible_ids    = visible_custom_field_ids                                       # break_glass: [] (bulk)
        visible_levels = visible_domain_levels                                          # emergency domains masked
        payload = ActiveModelSerializers::SerializableResource.new(
          clients,
          each_serializer: ClientSerializer,
          adapter: :json,
          visible_custom_field_ids: visible_ids,
          visible_domain_levels: visible_levels
        ).as_json
        serialized.concat(Array(payload[:clients] || payload['clients']))
      end
      serialized
    end

    def find_client_by(params)
      if params[:given_name] || params[:birth_province_id] || params[:current_province_id] || params[:date_of_birth] || params[:local_given_name] || params[:local_family_name] || params[:family_name]
        Client.filter(params)
      else
        []
      end
    end

    def set_organization_to_client(collections, value)
      collections.each { |collection| collection.organization = value }
    end
  end
end
