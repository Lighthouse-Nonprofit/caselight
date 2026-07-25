FactoryBot.define do
  factory :family_alert do
    association :family
    association :created_by, factory: :user
    severity { 'caution' }
    title { 'Wellness concern — read before visiting' }
    body { FFaker::Lorem.sentence }
  end
end
