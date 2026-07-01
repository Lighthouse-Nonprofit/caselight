# frozen_string_literal: true
require 'rails_helper'

# The READ IS THE GATE. These prove EnforcementSetting.enabled? resolves fail-safe: no row / nil column /
# ALL-NIL row / store error -> config_default (OFF today); only a literal persisted true enables. Runs in
# the 'app' tenant.
RSpec.describe EnforcementSetting, type: :model do
  before(:each) { EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }
  after(:each)  { EnforcementSetting.delete_all; EnforcementSetting.clear_cache! }

  describe '.enabled? (fail-safe resolver)' do
    it 'returns the config default when NO row exists (default OFF => OFF)' do
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_least_privilege, config_default: false)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_tenant_boundary, config_default: false)).to be(false)
    end

    it 'an ALL-NIL persisted row resolves IDENTICALLY to an absent row (both -> config_default)' do
      EnforcementSetting.create!(enforce_authorization: nil, enforce_least_privilege: nil, enforce_tenant_boundary: nil)
      EnforcementSetting.clear_cache!
      EnforcementSetting::FLAGS.each do |flag|
        expect(EnforcementSetting.enabled?(flag, config_default: false)).to be(false)
        expect(EnforcementSetting.enabled?(flag, config_default: true)).to be(true)
      end
    end

    it 'defers to the config default when the column is nil (no override)' do
      EnforcementSetting.create!(enforce_authorization: nil)
      EnforcementSetting.clear_cache!
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: true)).to be(true)
    end

    it 'honors an explicit persisted true (ON) regardless of config default' do
      EnforcementSetting.create!(enforce_authorization: true)
      EnforcementSetting.clear_cache!
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(true)
    end

    it 'honors an explicit persisted false (OFF) even when the config default is ON' do
      EnforcementSetting.create!(enforce_authorization: false)
      EnforcementSetting.clear_cache!
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: true)).to be(false)
    end

    it 'FAILS SAFE to the config default (never a spurious ON) when the store raises' do
      allow(EnforcementSetting).to receive(:current_override).and_raise(StandardError, 'db down')
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(false)
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: true)).to be(true)
    end

    it 'reads ONE row for all three flags per request (shared memo)' do
      EnforcementSetting.create!(enforce_authorization: true, enforce_least_privilege: true)
      EnforcementSetting.clear_cache!
      expect(EnforcementSetting).to receive(:load_overrides).once.and_call_original
      EnforcementSetting.enabled?(:enforce_authorization, config_default: false)
      EnforcementSetting.enabled?(:enforce_least_privilege, config_default: false)
      EnforcementSetting.enabled?(:enforce_tenant_boundary, config_default: false)
    end

    it 'a persisted ON survives a simulated restart (cache clear + re-read)' do
      EnforcementSetting.create!(enforce_authorization: true)
      EnforcementSetting.clear_cache! # simulate a fresh process/request
      expect(EnforcementSetting.enabled?(:enforce_authorization, config_default: false)).to be(true)
    end
  end

  describe '.for_display (a GET must never persist)' do
    it 'returns an unsaved row when none exists' do
      row = EnforcementSetting.for_display
      expect(row).not_to be_persisted
      expect(EnforcementSetting.count).to eq(0)
    end
  end
end
