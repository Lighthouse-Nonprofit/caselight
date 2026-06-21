# frozen_string_literal: true
# Build-time only (PRECOMPILE_ASSETS=true); no DB or S3 is reachable during the Docker
# image asset precompile. NO runtime effect (the flag is unset at runtime).
# See NOTES.md findings #6 and #7.
if ENV['PRECOMPILE_ASSETS'] == 'true'
  # (1) devise_token_auth probes the schema via table_exists? at class-load when User
  #     loads (thredded engine forces this). Degrade it to false with no DB reachable.
  module OscarPrecompileNoDb
    def table_exists?(*)
      super
    rescue StandardError
      false
    end
  end
  ActiveRecord::Base.singleton_class.prepend(OscarPrecompileNoDb)

  # (2) asset_sync hooks assets:precompile to upload to S3. Disable it on the config
  #     object directly (the ASSET_SYNC_ENABLED env var did not take). after_initialize
  #     runs after asset_sync's engine configures and before the precompile rake hook
  #     checks run_on_precompile.
  Rails.application.config.after_initialize do
    if defined?(AssetSync) && AssetSync.respond_to?(:config) && AssetSync.config
      AssetSync.config.run_on_precompile = false
      AssetSync.config.enabled = false
    end
  end
end
