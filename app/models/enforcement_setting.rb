# frozen_string_literal: true

# EnforcementSetting — the PERSISTED, RUNTIME-MUTABLE overlay for the three Phase-5 enforcement flags
# (NIST AC-3 / CM-5). Named specifically (NOT a generic `Setting`) so it reads as SECURITY infrastructure
# and never tempts anyone to stuff org data in it (CLAUDE.md: org data -> the config/extensibility layer;
# app-level enforcement config as a model is fine).
#
# SINGLETON ROW PER TENANT. Each column is NULLABLE THREE-STATE:
#   nil   => no override -> the predicate uses the config.x/ENV boot default (fail-safe = today = OFF)
#   true  => explicit persisted ON
#   false => explicit persisted OFF
# With no row (or an all-nil row) every `enabled?` returns config_default -> byte-identical to today.
#
# THE READ IS THE GATE. `enabled?` is the ONE method all three per-request predicates + both shadow
# detectors call, so they resolve + fail identically. It NEVER raises and NEVER returns a truthy sentinel
# on error: ANY failure (missing table pre-migration, DB blip, public/no-tenant schema, exception) ->
# config_default (which is false/OFF for all three today). Only a literal persisted `true` enables.
class EnforcementSetting < ApplicationRecord
  # The exact set of flags this store overlays. An unknown flag is a programming error, not a silent miss.
  FLAGS = %i[enforce_authorization enforce_least_privilege enforce_tenant_boundary].freeze

  # NEW boolean three-state setting that rides the SAME enabled? path as FLAGS but is NOT part of FLAGS,
  # so the shadow-rendering view loop + compute_changes iteration over FLAGS are untouched. require_mfa's
  # config default is FALSE (today = only mfa_privileged? users are nudged).
  BOOL_EXTRA = %i[require_mfa].freeze

  # NEW value settings (minutes / count / days). NULL/blank => the Devise config default (fail-safe = today).
  # These do NOT go through enabled? (which is boolean); they go through effective_value.
  VALUE_SETTINGS = %i[idle_timeout_minutes lockout_max_attempts lockout_unlock_in_minutes password_max_age_days].freeze

  # HARD lockout floor (AC-7 admin-brick prevention): fewer than 3 attempts would lock an admin after a
  # couple of typos. REJECTED at write (validation below) AND clamped at read (User.maximum_attempts uses
  # [v, LOCKOUT_ATTEMPTS_FLOOR].max) so even a hand-edited/console row can never lock after 1-2 failures.
  LOCKOUT_ATTEMPTS_FLOOR = 3

  # Range validation so a bad value can NEVER be stored (update! raises RecordInvalid -> the panel
  # re-renders with the error rather than bricking auth). allow_nil keeps the three-state "unset => default".
  validates :idle_timeout_minutes,      numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 1440 }, allow_nil: true
  validates :lockout_max_attempts,      numericality: { only_integer: true, greater_than_or_equal_to: LOCKOUT_ATTEMPTS_FLOOR, less_than_or_equal_to: 100 }, allow_nil: true
  validates :lockout_unlock_in_minutes, numericality: { only_integer: true, greater_than_or_equal_to: 5, less_than_or_equal_to: 1440 }, allow_nil: true
  validates :password_max_age_days,     numericality: { only_integer: true, greater_than_or_equal_to: 1, less_than_or_equal_to: 3650 }, allow_nil: true

  belongs_to :updated_by, class_name: 'User', optional: true

  # Resolve a flag to its EFFECTIVE boolean: persisted override if the row carries a non-nil value for it,
  # ELSE the config.x boot default. config_default MUST be passed by the caller (each predicate passes its
  # own `config.x.<flag> == true`) so this method has no hidden dependency on which flag maps to which
  # config key. Fails SAFE to config_default on ANY error.
  #
  #   EnforcementSetting.enabled?(:enforce_authorization,
  #     config_default: Rails.application.config.x.enforce_authorization == true)
  def self.enabled?(flag, config_default:)
    override = current_override(flag) # per-request memoized; true / false / nil
    return config_default if override.nil? # no override => today's behavior (config.x default)

    override == true # only a LITERAL persisted true enables; false => OFF
  rescue StandardError => e
    Rails.logger.error("[EnforcementSetting] enabled?(#{flag}) failed (fail-safe -> config default): #{e.class}: #{e.message}")
    config_default == true
  end

  # Per-request memo (RequestStore auto-clears each request; the gem is already loaded via its Railtie —
  # see the Gemfile note in the apply package). ONE query per request for all three flags (they share one
  # row), and repeat predicate calls in a request are free. Keyed by the current Apartment tenant so a
  # pooled RequestStore can never serve tenant A's overrides to tenant B within one request.
  def self.current_override(flag)
    RequestStore.store[memo_key] ||= load_overrides
    RequestStore.store[memo_key][flag]
  end

  def self.memo_key
    tenant = (Apartment::Tenant.current rescue nil)
    :"enforcement_overrides_#{tenant}"
  end

  # ONE query per request. Any failure (table absent pre-migration, public/no-tenant schema, DB down)
  # returns an EMPTY hash -> every flag reads nil -> every `enabled?` returns config_default (fail-safe OFF).
  # NEVER auto-seeds a row (an auto-seeded row would make "absent" impossible and could clobber a
  # persisted ON on the next deploy) — read-only here; only the controller writes.
  def self.load_overrides
    row = first
    return {} if row.nil?

    { enforce_authorization: row.enforce_authorization,
      enforce_least_privilege: row.enforce_least_privilege,
      enforce_tenant_boundary: row.enforce_tenant_boundary,
      # new three-state boolean (rides enabled?)
      require_mfa: row.require_mfa,
      # new integer VALUE settings (ride effective_value)
      idle_timeout_minutes: row.idle_timeout_minutes,
      lockout_max_attempts: row.lockout_max_attempts,
      lockout_unlock_in_minutes: row.lockout_unlock_in_minutes,
      password_max_age_days: row.password_max_age_days }
  rescue StandardError => e
    Rails.logger.error("[EnforcementSetting] load_overrides failed (fail-safe -> config default): #{e.class}: #{e.message}")
    {}
  end

  # The single editable row for this tenant, CREATED lazily on WRITE only (the controller #update path).
  # NOTE: #show must NOT use this (a GET must never persist) — #show uses `first || new` instead.
  def self.instance
    first_or_create!
  end

  # Non-persisting accessor for the settings PAGE render (a GET must not write a row). Returns the existing
  # row or an unsaved in-memory default (all-nil columns => resolves identically to absent => config.x).
  def self.for_display
    first || new
  end

  # Bust the per-request memo after a write so the SAME request's post-write reads are fresh; because the
  # memo is request-scoped, the very next request re-reads the row and reflects the flip ("promptly" =
  # next request — which sidesteps the config.x restart problem entirely). No stale global state.
  def self.clear_cache!
    RequestStore.store.delete(memo_key)
  end

  # config.x boot default for a flag — the SINGLE mapping of flag -> config key, reused by #effective. All
  # three default false today.
  def self.config_default_for(flag)
    Rails.application.config.x.public_send(flag) == true
  end

  # The EFFECTIVE state (override applied) for display + audit-diff. Uses the SAME resolver as the gate.
  def effective(flag)
    self.class.enabled?(flag, config_default: self.class.config_default_for(flag))
  end

  # Resolve a VALUE setting to its EFFECTIVE integer: the persisted override if the row carries a
  # non-blank value, ELSE the caller-supplied config_default. MIRRORS enabled? exactly: per-request
  # memoized via the SAME tenant-keyed current_override, and FAILS SAFE to config_default on ANY error.
  # Never raises. Never auto-seeds (current_override is read-only).
  #
  #   EnforcementSetting.effective_value(:idle_timeout_minutes,
  #     config_default: EnforcementSetting.config_default_for_value(:idle_timeout_minutes))
  def self.effective_value(key, config_default:)
    override = current_override(key) # per-request memoized; Integer / nil
    return config_default if override.blank?

    Integer(override)
  rescue StandardError => e
    Rails.logger.error("[EnforcementSetting] effective_value(#{key}) failed (fail-safe -> config default): #{e.class}: #{e.message}")
    config_default
  end

  # The Devise config default for a VALUE setting in its NATIVE unit (minutes / count / days) — the SINGLE
  # key->Devise mapping, reused by the User overrides' fallback and the panel's placeholder hints.
  # password_max_age_days has NO Devise expiry concept => nil (unset = OFF).
  def self.config_default_for_value(key)
    case key
    when :idle_timeout_minutes      then (Devise.timeout_in.to_i / 60)
    when :lockout_max_attempts      then Devise.maximum_attempts
    when :lockout_unlock_in_minutes then (Devise.unlock_in.to_i / 60)
    when :password_max_age_days     then nil
    end
  end

  # EFFECTIVE value (override applied) for display + audit. Same resolver as the runtime reads.
  def effective_value(key)
    self.class.effective_value(key, config_default: self.class.config_default_for_value(key))
  end
end
