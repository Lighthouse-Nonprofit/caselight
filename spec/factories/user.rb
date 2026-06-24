FactoryBot.define do
  factory :user do
    sequence(:email)  { |n| "#{n}#{FFaker::Internet.email}" }
    first_name { FFaker::Name.first_name }
    last_name { FFaker::Name.last_name }
    # Complexity-compliant (devise-security :secure_validatable): >=12 chars, upper/lower/digit/symbol.
    password { 'SecurePass123!' }
    password_confirmation { 'SecurePass123!' }
    roles { 'case worker' }
    program_warning { true }
    staff_performance_notification { true }

    trait :case_worker do
      roles { 'case worker' }
    end

    trait :able_manager do
      roles { 'able manager' }
    end

    trait :ec_manager do
      roles { 'ec manager' }
    end

    trait :kc_manager do
      roles { 'kc manager' }
    end

    trait :fc_manager do
      roles { 'fc manager' }
    end

    trait :admin do
      roles { 'admin' }
    end

    trait :strategic_overviewer do
      roles { 'strategic overviewer' }
    end

    trait :manager do
      roles { 'manager' }
    end
  end
end
