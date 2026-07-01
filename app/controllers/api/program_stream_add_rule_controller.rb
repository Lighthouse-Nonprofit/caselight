module Api
  class ProgramStreamAddRuleController < AdminController
    # Phase 5.6 (AC-3) allowlist (only: [:get_fields]): AJAX rule-builder field descriptors -- metadata
    # only, no authorizable resource.
    skip_authorization_check only: [:get_fields]

    def get_fields
      @program_stream_fields = AdvancedSearches::RuleFields.new(user: current_user).render
      render json: @program_stream_fields
    end
  end
end
