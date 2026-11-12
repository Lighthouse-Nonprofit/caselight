# frozen_string_literal: true
# Build-time only (PRECOMPILE_ASSETS=true); no DB is reachable during the Docker
# image asset precompile. NO runtime effect (the flag is unset at runtime).
# (History: the EOL-era build log, findings #6 and #7, lives owner-side.)
if ENV['PRECOMPILE_ASSETS'] == 'true'
  # Class-load schema probes (table_exists?, originally devise_token_auth, since removed)
  # degrade to false with no DB reachable.
  module OscarPrecompileNoDb
    def table_exists?(*)
      super
    rescue StandardError
      false
    end
  end
  ActiveRecord::Base.singleton_class.prepend(OscarPrecompileNoDb)
end
