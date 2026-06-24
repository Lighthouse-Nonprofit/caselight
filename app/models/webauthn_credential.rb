# A registered WebAuthn passkey (FIDO2 credential) bound to a User. ADDITIVE login factor alongside
# password + TOTP. Tenant-scoped (lives in the tenant schema with users). See CreateWebauthnCredentials.
class WebauthnCredential < ApplicationRecord
  belongs_to :user

  validates :external_id, presence: true, uniqueness: true
  validates :public_key,  presence: true
  validates :sign_count,  presence: true
  validates :nickname,    presence: true, uniqueness: { scope: :user_id }
end
