# frozen_string_literal: true
# Proves the fail-safe VALUE resolver + validations + per-tenant isolation for the 4 runtime toggles.
# Runs against the test tenant (Apartment). Use the js-EXCLUDING rspec subset (project CI gotcha).
# RequestStore.clear! between reads (the memo is per-request, tenant-keyed).
require 'rails_helper'

RSpec.describe EnforcementSetting, type: :model do
  before { RequestStore.clear! }

  describe '.effective_value fail-safe (unset => config default) — (a)' do
    it 'returns the passed config_default when no row exists' do
      expect(EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: 30)).to eq(30)
      expect(EnforcementSetting.effective_value(:lockout_max_attempts, config_default: 10)).to eq(10)
      expect(EnforcementSetting.effective_value(:password_max_age_days, config_default: nil)).to be_nil
    end

    it 'returns config_default when the column is nil on a persisted row' do
      EnforcementSetting.create!(idle_timeout_minutes: nil)
      RequestStore.clear!
      expect(EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: 30)).to eq(30)
    end

    it 'fails SAFE to config_default on any error (rescue) — (a)' do
      allow(EnforcementSetting).to receive(:current_override).and_raise(StandardError)
      expect(EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: 30)).to eq(30)
    end

    it 'NEVER auto-seeds a row on read' do
      expect { EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: 30) }
        .not_to change(EnforcementSetting, :count)
      expect { EnforcementSetting.for_display }.not_to change(EnforcementSetting, :count)
    end
  end

  describe '.effective_value enforces when set — (b)' do
    it 'returns the persisted integer' do
      EnforcementSetting.create!(idle_timeout_minutes: 15, lockout_max_attempts: 5, lockout_unlock_in_minutes: 30, password_max_age_days: 90)
      RequestStore.clear!
      expect(EnforcementSetting.effective_value(:idle_timeout_minutes, config_default: 30)).to eq(15)
      expect(EnforcementSetting.effective_value(:lockout_max_attempts, config_default: 10)).to eq(5)
      expect(EnforcementSetting.effective_value(:lockout_unlock_in_minutes, config_default: 60)).to eq(30)
      expect(EnforcementSetting.effective_value(:password_max_age_days, config_default: nil)).to eq(90)
    end
  end

  describe 'admin-lockout safety validations — (c)' do
    it 'REJECTS a lockout threshold below the floor of 3 (cannot be persisted)' do
      s = EnforcementSetting.new(lockout_max_attempts: 1)
      expect(s).not_to be_valid
      expect(s.errors[:lockout_max_attempts]).to be_present
      expect { EnforcementSetting.create!(lockout_max_attempts: 2) }.to raise_error(ActiveRecord::RecordInvalid)
    end

    it 'accepts a lockout threshold at the floor and rejects out-of-range values' do
      expect(EnforcementSetting.new(lockout_max_attempts: 3)).to be_valid
      expect(EnforcementSetting.new(idle_timeout_minutes: 0)).not_to be_valid
      expect(EnforcementSetting.new(idle_timeout_minutes: 1441)).not_to be_valid
      expect(EnforcementSetting.new(lockout_unlock_in_minutes: 4)).not_to be_valid
      expect(EnforcementSetting.new(password_max_age_days: 0)).not_to be_valid
      expect(EnforcementSetting.new(password_max_age_days: 3650)).to be_valid
    end
  end

  describe 'require_mfa three-state via enabled?' do
    it 'defaults OFF when unset and reads the persisted value when set' do
      expect(EnforcementSetting.enabled?(:require_mfa, config_default: false)).to eq(false)
      EnforcementSetting.create!(require_mfa: true)
      RequestStore.clear!
      expect(EnforcementSetting.enabled?(:require_mfa, config_default: false)).to eq(true)
    end
  end

  describe 'per-tenant isolation — (d)' do
    # The isolation guarantee is the tenant-keyed per-request memo (memo_key embeds Apartment::Tenant.current),
    # so within a pooled RequestStore one tenant can never be served another tenant's cached overrides. We
    # test that MECHANISM directly (stubbing the current tenant) rather than provisioning two live schemas —
    # schema switching in the test DB is fixture-dependent, the memo_key is what actually prevents the bleed.
    it 'keys the per-request override memo by tenant, so one tenant is never served another tenant cache' do
      allow(Apartment::Tenant).to receive(:current).and_return('tenant_a')
      key_a = EnforcementSetting.memo_key
      allow(Apartment::Tenant).to receive(:current).and_return('tenant_b')
      key_b = EnforcementSetting.memo_key
      expect(key_a).not_to eq(key_b) # distinct tenants => distinct memo slots

      # Prime tenant A's memo with an override, then read under tenant B: B reads its OWN (empty) slot and
      # falls through to load_overrides (no row => {} => nil) — it does NOT see tenant A's primed value.
      RequestStore.clear!
      RequestStore.store[key_a] = { idle_timeout_minutes: 5 }

      allow(Apartment::Tenant).to receive(:current).and_return('tenant_a')
      expect(EnforcementSetting.current_override(:idle_timeout_minutes)).to eq(5)

      allow(Apartment::Tenant).to receive(:current).and_return('tenant_b')
      expect(EnforcementSetting.current_override(:idle_timeout_minutes)).to be_nil
    end
  end
end
