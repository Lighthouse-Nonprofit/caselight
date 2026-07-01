# frozen_string_literal: true
# Proves the Devise overrides on User honor the per-tenant setting and FAIL SAFE to the config defaults,
# including the password-expiry neutralizer + stamping.
require 'rails_helper'

RSpec.describe User, type: :model do
  before { RequestStore.clear! }

  describe 'fail-safe (all settings unset => today) — (a)' do
    it 'uses the Devise config defaults' do
      user = build(:user)
      expect(user.timeout_in).to eq(30.minutes)       # Devise.timeout_in
      expect(User.maximum_attempts).to eq(10)          # Devise.maximum_attempts (super)
      expect(User.unlock_in).to eq(1.hour)             # Devise.unlock_in (super)
      expect(User.expire_password_after).to eq(false)  # NEUTRALIZER: never the gem 3.months default
    end
  end

  describe 'enforces when set — (b)' do
    before do
      EnforcementSetting.create!(idle_timeout_minutes: 15, lockout_max_attempts: 5, lockout_unlock_in_minutes: 30, password_max_age_days: 90)
      RequestStore.clear!
    end

    it 'reflects the per-tenant setting at the true Devise seams' do
      expect(build(:user).timeout_in).to eq(15.minutes)
      expect(User.maximum_attempts).to eq(5)
      expect(User.unlock_in).to eq(30.minutes)
      expect(User.expire_password_after).to eq(90.days)
    end
  end

  describe 'lockout floor clamp at read (defense in depth) — (c)' do
    it 'clamps a below-floor stored value up to 3 even if it bypassed validation' do
      # Simulate a hand-edited/console bad row (update_column skips validation); the reader must still floor.
      EnforcementSetting.create!.update_column(:lockout_max_attempts, 1)
      RequestStore.clear!
      expect(User.maximum_attempts).to eq(3)
    end
  end

  describe 'password expiry (Toggle 4) — stamping + predicates' do
    it 'stamps password_changed_at on create and expires only when aged past the max' do
      user = create(:user)
      expect(user.password_changed_at).to be_present # gem before_save stamped it

      # Feature OFF (no max set) => never expired, regardless of age.
      user.update_column(:password_changed_at, 400.days.ago)
      expect(user.reload.need_change_password?).to eq(false)

      # Feature ON => aged password expires; fresh does not.
      EnforcementSetting.create!(password_max_age_days: 30)
      RequestStore.clear!
      user.update_column(:password_changed_at, 60.days.ago)
      expect(user.reload.password_expired?).to eq(true)
      user.update_column(:password_changed_at, 5.days.ago)
      expect(user.reload.password_expired?).to eq(false)
    end
  end
end
