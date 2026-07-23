FactoryBot.define do
  factory :family_note do
    association :family
    association :user
    meeting_date { Date.today }
    attendee { 'Weekly case conference' }
    note { FFaker::Lorem.paragraph }
  end
end
