require 'rails_helper'

# Phase 2 — WebAuthn passkeys (FedRAMP IA-2). Model-level validations + association.
RSpec.describe WebauthnCredential, type: :model do
  let(:user) { create(:user) }

  it 'belongs to a user' do
    cred = create(:webauthn_credential, user: user)
    expect(cred.user).to eq(user)
  end

  it 'is destroyed when its user is destroyed' do
    create(:webauthn_credential, user: user)
    expect { user.destroy }.to change(WebauthnCredential, :count).by(-1)
  end

  it 'requires external_id, public_key, nickname, sign_count' do
    cred = WebauthnCredential.new(user: user, external_id: nil, public_key: nil, nickname: nil, sign_count: nil)
    expect(cred).not_to be_valid
    expect(cred.errors.attribute_names).to include(:external_id, :public_key, :nickname, :sign_count)
  end

  it 'enforces a globally-unique external_id' do
    create(:webauthn_credential, external_id: 'dup-ext-id')
    dup = build(:webauthn_credential, external_id: 'dup-ext-id')
    expect(dup).not_to be_valid
    expect(dup.errors.attribute_names).to include(:external_id)
  end

  it 'enforces a nickname unique per user' do
    create(:webauthn_credential, user: user, nickname: 'YubiKey')
    dup = build(:webauthn_credential, user: user, nickname: 'YubiKey')
    expect(dup).not_to be_valid
    expect(dup.errors.attribute_names).to include(:nickname)
  end

  it 'allows the same nickname for a different user' do
    create(:webauthn_credential, user: user, nickname: 'YubiKey')
    other = create(:webauthn_credential, user: create(:user), nickname: 'YubiKey')
    expect(other).to be_persisted
  end
end
