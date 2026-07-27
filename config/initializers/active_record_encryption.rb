# ActiveRecord Encryption keys — FedRAMP SC-12/SC-13/SC-28, SOC 2 C1.1.
# Foundation for application-layer encryption at rest: devise-two-factor's encrypted otp_secret
# (Phase 2 MFA) and the PII field encryption coming in Phase 4.
#
# Key handling:
#   - PRODUCTION supplies dedicated, STABLE keys via ENV (AR_ENCRYPTION_*) — these must persist for
#     the life of the data (rotating them orphans existing ciphertext). They belong in the box .env /
#     a real secrets manager (the AWS Secrets Manager hand-off; see SECURITY.md). NOT committed.
#   - DEV / TEST / CI derive keys deterministically from secret_key_base (data is synthetic and
#     disposable), so there are no hard-coded secrets in the repo and no setup needed locally / in CI.
#
# configure() applies immediately (not dependent on railtie ordering).
key_base = Rails.application.secret_key_base.to_s

ActiveRecord::Encryption.configure(
  primary_key:         ENV['AR_ENCRYPTION_PRIMARY_KEY'].presence         || Digest::SHA256.hexdigest("#{key_base}::ar-encryption-primary"),
  deterministic_key:   ENV['AR_ENCRYPTION_DETERMINISTIC_KEY'].presence   || Digest::SHA256.hexdigest("#{key_base}::ar-encryption-deterministic"),
  key_derivation_salt: ENV['AR_ENCRYPTION_KEY_DERIVATION_SALT'].presence || Digest::SHA256.hexdigest("#{key_base}::ar-encryption-salt")
)

# STRICT MODE (cutover 2026-07-26): a non-envelope value read from an encrypted column now RAISES
# (ActiveRecord::Encryption::Errors::Decryption) instead of being tolerated. The Phase-4 migration
# window (support_unencrypted_data=true, which let plaintext rows read while the per-tenant
# backfills ran) is closed — the flip was gated on `rake encryption:verify` PASSing every tier in
# every tenant on dev AND the pilot box, which it does. The sanctioned migration tasks
# (encryption:backfill / encryption:reencrypt_client_names) re-enable the window for their OWN
# rake process only — they are the healing path for any future straggler, which strict mode would
# otherwise make unreadable and unfixable. Set on the config object directly so it applies
# regardless of initializer/railtie ordering.
ActiveRecord::Encryption.config.support_unencrypted_data = false

# UX round 3 (C1) — extend deterministic queries so WHERE clauses on encrypted columns also
# probe (a) the downcased value for ignore_case columns (the Tier-4 names) and (b) `previous:`
# scheme ciphertext (rows not yet rewritten by encryption:reencrypt_client_names). The third
# branch — cleartext probing — self-disabled with the strict-mode cutover above (it only ran
# while support_unencrypted_data was on). The app doesn't use load_defaults, so the framework
# default (off) applied and the railtie never installed the query extension — set the flag AND
# install the module here, in this file's ordering-independent style.
ActiveRecord::Encryption.config.extend_queries = true
ActiveRecord::Encryption::ExtendedDeterministicQueries.install_support
