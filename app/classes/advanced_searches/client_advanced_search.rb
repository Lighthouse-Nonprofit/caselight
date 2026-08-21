module AdvancedSearches
  class ClientAdvancedSearch
    def initialize(basic_rules, clients)
      @clients            = clients
      @basic_rules        = basic_rules
    end

    def filter
      query_array         = []
      client_base_sql     = AdvancedSearches::ClientBaseSqlBuilder.new(@clients, @basic_rules).generate

      # If every rule was unrecognized/skipped (see the guard in ClientBaseSqlBuilder), the SQL string is
      # blank — `where([''])` is invalid SQL, so return the base scope unfiltered instead of crashing.
      return @clients if client_base_sql[:sql_string].blank?

      query_array << client_base_sql[:sql_string]
      client_base_values  = client_base_sql[:values].map{ |v| query_array << v }

      @clients.where(query_array)
    end
  end
end
