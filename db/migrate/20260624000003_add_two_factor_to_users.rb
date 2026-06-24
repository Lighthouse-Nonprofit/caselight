class AddTwoFactorToUsers < ActiveRecord::Migration[7.2]
  # devise-two-factor (TOTP MFA) columns — FedRAMP IA-2(1). Tenant-scoped (users), so production
  # applies these per tenant via `rake apartment:migrate` alongside the shared `rake db:migrate`.
  #
  #  - otp_secret: the TOTP shared secret, stored ENCRYPTED (encrypts :otp_secret + ActiveRecord
  #    Encryption). `text` to comfortably hold the ciphertext envelope.
  #  - consumed_timestep: last consumed TOTP step — prevents code replay within its validity window.
  #  - otp_required_for_login: per-user MFA toggle. Defaults FALSE (opt-in; MFA stays dormant until a
  #    user enrolls — the enrollment UI + login OTP step land in a follow-up).
  #  - otp_backup_codes: one-time recovery codes (:two_factor_backupable), stored hashed.
  def change
    add_column :users, :otp_secret,             :text
    add_column :users, :consumed_timestep,      :integer
    add_column :users, :otp_required_for_login, :boolean, null: false, default: false
    add_column :users, :otp_backup_codes,       :string, array: true
  end
end
