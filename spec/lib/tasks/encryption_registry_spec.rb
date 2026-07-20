# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 4 (SC-28 / SOC 2 C1.1) — DRIFT guard between the encryption.rake ENCRYPTION_TIERS registry
# and the models' ACTUAL `encrypts`-declared attributes.
#
# encryption:verify only inspects the columns the registry names: it aborts if a LISTED column is not
# `encrypts`-declared (would write plaintext), but the REVERSE — every `encrypts`-declared column is
# named in some tier — is unguarded. A new PII field (or the eventual `encrypts :exit_note` on Case,
# POAM-012) added without a registry entry is a permanent plaintext straggler that `verify` still
# reports PASS on, opening an SC-28 hole at the support_unencrypted_data=false cutover. spec/lib/tasks/
# encryption_backfill_spec.rb hardcodes a TIER1 copy, so rake<->spec drift is invisible there.
#
# This spec loads the REAL ENCRYPTION_TIERS constant from the rake (co-defined with the tasks in
# lib/tasks/encryption.rake) — never a local copy — and cross-checks it against encrypted_attributes
# in BOTH directions, then across every eager-loaded model. Pure reflection: no tenant data, no DB
# writes. Rails 8.1 zeitwerk/eager-load changes make silent model-set drift more likely, so eager-load
# the whole app before asserting the model set is fully covered.
RSpec.describe 'ENCRYPTION_TIERS registry <-> encrypted_attributes drift' do
  before(:all) do
    # Load the rake file so its top-level ENCRYPTION_TIERS constant (and the encryption:* tasks it is
    # co-defined with) exist in-process — same idiom as accounts_spec/privacy_spec/retention_spec.
    Rake.application.rake_require('tasks/encryption', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
    # Force the full model set to load so ActiveRecord::Base.descendants is complete (test env does not
    # eager-load by default); otherwise a newly-encrypted, never-referenced model would be invisible.
    Rails.application.eager_load!
  end

  # GEM-MANAGED encrypted credentials that are INTENTIONALLY absent from ENCRYPTION_TIERS.
  # ENCRYPTION_TIERS is the app's PII backfill/verify registry (Phase-6 PII inventory + subject-access
  # export). devise-two-factor's `:two_factor_authenticatable` strategy declares `encrypts :otp_secret`
  # (app/models/user.rb L12) — a TOTP CREDENTIAL, not PII, generated fresh at 2FA enrollment (nothing to
  # backfill). It is deliberately outside the PII tiers, so the reverse-direction drift check exempts it.
  # Any NEW app-declared encrypted PII column still trips the guard (this list is a closed, reviewed set).
  GEM_MANAGED_ENCRYPTED = { 'User' => %i[otp_secret] }.freeze

  # Model-name strings that appear as a tier key somewhere in the registry.
  def registered_model_names
    ENCRYPTION_TIERS.values.flat_map(&:keys).uniq
  end

  # Flatten the registry to [tier, model_name, column] rows.
  def registry_entries
    ENCRYPTION_TIERS.flat_map do |tier, models|
      models.flat_map { |model_name, cols| cols.map { |c| [tier, model_name, c.to_sym] } }
    end
  end

  it 'loads the real ENCRYPTION_TIERS registry from encryption.rake (not a hardcoded copy)' do
    # The constant and the encryption:* tasks live in the SAME rake file, so proving the tasks are
    # defined proves the constant we assert against came from the rake, not a local duplicate.
    expect(Rake::Task.task_defined?('encryption:backfill')).to be(true)
    expect(Rake::Task.task_defined?('encryption:verify')).to be(true)
    expect(defined?(ENCRYPTION_TIERS)).to eq('constant')

    expect(ENCRYPTION_TIERS).to be_a(Hash)
    expect(ENCRYPTION_TIERS).to be_frozen
    expect(ENCRYPTION_TIERS).not_to be_empty

    ENCRYPTION_TIERS.each do |tier, models|
      expect(tier).to be_a(String)
      expect(models).to be_a(Hash)
      models.each do |model_name, cols|
        expect(model_name).to be_a(String)
        expect(cols).to be_an(Array)
        expect(cols).to all(be_a(Symbol)), "#{tier}/#{model_name} column list must be all symbols"
      end
    end
  end

  it 'declares `encrypts` for every (model, column) named in the registry' do
    registry_entries.each do |tier, model_name, column|
      model    = model_name.constantize
      declared = model.encrypted_attributes.to_a # nil-safe: nil.to_a == []
      expect(declared).to include(column),
        "ENCRYPTION_TIERS[#{tier.inspect}] lists #{model_name}##{column} but the model does not " \
        '`encrypts` it — backfill would write PLAINTEXT via update_columns and verify cannot vouch for it'
    end
  end

  it 'covers every encrypted attribute of each registered model in exactly one tier' do
    registered_model_names.each do |model_name|
      model  = model_name.constantize
      listed = registry_entries.select { |_tier, m, _col| m == model_name }

      exempt = GEM_MANAGED_ENCRYPTED[model_name] || []
      (model.encrypted_attributes.to_a - exempt).each do |attr|
        tiers_for = listed.select { |_tier, _m, col| col == attr }.map(&:first)
        expect(tiers_for.size).to eq(1),
          "#{model_name}##{attr} is `encrypts`-declared but appears in #{tiers_for.size} " \
          "ENCRYPTION_TIERS entr(y/ies) #{tiers_for.inspect}; every encrypted column must live in " \
          'exactly one tier (0 = an un-covered plaintext straggler verify would falsely PASS; ' \
          '>1 = a duplicated entry)'
      end
    end
  end

  it 'registers every eager-loaded model that declares encrypted attributes' do
    registered = registered_model_names

    offenders = ActiveRecord::Base.descendants.select do |model|
      next false if model.abstract_class?
      next false unless model.respond_to?(:encrypted_attributes)
      next false unless model.encrypted_attributes.present?
      # STI-safe: a child inherits its base's encrypts; registering the base (the family that owns the
      # declaration) is sufficient.
      ([model.name, model.base_class.name] & registered).empty?
    end

    expect(offenders).to be_empty,
      'these eager-loaded models declare `encrypts` but are absent from ENCRYPTION_TIERS: ' \
      "#{offenders.map(&:name).join(', ')} — register each new PII model in a tier so backfill/" \
      'verify can cover it before the support_unencrypted_data=false cutover (e.g. an eventual ' \
      '`encrypts :exit_note` on Case, POAM-012, must be added to the registry)'
  end
end
