FactoryBot.define do
  factory :webauthn_credential do
    user
    sequence(:external_id) { |n| "credential-external-id-#{n}" }
    public_key { 'cose-public-key-placeholder' }
    sequence(:nickname) { |n| "Passkey #{n}" }
    sign_count { 0 }
  end
end
