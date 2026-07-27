module Api
  class ClientsController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:compare]): duplicate-detection JSON behind the client
    # form's save button. POAM-AC3-COMPARE (closed 2026-07-26): the endpoint is CURRENT-TENANT-ONLY
    # (the Phase-5-era cross-org Organization.switch_to loop is gone), returns the MINIMAL payload
    # the JS consumer actually reads ({id, organization} — never record values), and requires a
    # NAME field (province/DOB alone cannot enumerate; they only narrow a name match). Every probe
    # writes a values-free client_compare_probe AccessLog. skip_authorization_check stays: the
    # response carries no record values, and warning about a duplicate must not require per-record
    # :read on the duplicate.
    skip_authorization_check only: [:compare]

    def compare
      clients = find_client_by(params)
      log_compare_probe(clients.size)
      org_name = Organization.current.try(:full_name)
      render json: { clients: clients.map { |client| { id: client.id, organization: org_name } } }
    end

    private

    # A NAME field is required — deterministic-ciphertext equality on the Tier-4 name columns.
    # DOB / province act only as narrowing clauses inside Client.filter, never sufficient alone.
    def find_client_by(params)
      return [] unless params[:given_name].present? || params[:family_name].present? ||
                       params[:local_given_name].present? || params[:local_family_name].present?

      Client.filter(params)
    end

    # Values-free probe audit (AU-2): who asked and how many matched — never which values.
    # scrub_query: the probe is a GET whose query string IS the client's name — keep it out.
    def log_compare_probe(match_count)
      AccessLog.security_event!(
        event_type:  'client_compare_probe',
        request:     request,
        user:        current_user,
        metadata:    { 'surface' => 'client_duplicate_check', 'matches' => match_count },
        scrub_query: true
      )
    end
  end
end
