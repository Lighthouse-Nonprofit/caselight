class CreateWebauthnCredentials < ActiveRecord::Migration[7.2]
  # WebAuthn passkeys — FedRAMP IA-2 (phishing-resistant authenticator). ADDITIVE to password + TOTP.
  #
  # TENANT-SCOPED: like `users` (Apartment excludes only Organization), so production applies this per
  # tenant via `rake apartment:migrate` alongside the shared `rake db:migrate`. Keeping credentials in
  # the tenant schema is a security property — a passkey cannot authenticate into the wrong tenant.
  #
  # Columns:
  #  - external_id: the credential's WebAuthn ID, base64url. The lookup key on authentication; UNIQUE.
  #  - public_key:  the COSE public key (base64). Not secret, stored plaintext (no AR Encryption needed).
  #  - nickname:    human label (e.g. "YubiKey"); unique per user so the management list is unambiguous.
  #  - sign_count:  authenticator signature counter for cloned-authenticator detection (some platform
  #                 authenticators always report 0 — tolerated; a DECREASE is what's rejected).
  #  - last_used_at: surfaced in the management UI; nil until first use.
  #
  # Also adds users.webauthn_id: a stable, non-PII WebAuthn user handle (base64url), populated lazily on
  # first registration. Kept separate from the legacy token-auth `uid` (which defaults to '' and pairs
  # with `provider`).
  def change
    create_table :webauthn_credentials do |t|
      t.references :user, null: false, foreign_key: true
      t.string :external_id, null: false
      t.string :public_key,  null: false
      t.string :nickname,    null: false
      t.bigint :sign_count,  null: false, default: 0
      t.datetime :last_used_at

      t.timestamps
    end

    add_index :webauthn_credentials, :external_id, unique: true
    add_index :webauthn_credentials, %i[user_id nickname], unique: true

    add_column :users, :webauthn_id, :string
  end
end
