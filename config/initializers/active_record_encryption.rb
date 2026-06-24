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

# Don't raise if a plaintext value is read from a not-yet-encrypted column during the Phase 4
# migration window (lets us encrypt existing rows incrementally). Set on the config object
# directly so it applies regardless of initializer/railtie ordering.
ActiveRecord::Encryption.config.support_unencrypted_data = true
