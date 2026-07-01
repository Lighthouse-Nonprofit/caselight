# frozen_string_literal: true

# EnforcementSettingsController — the ADMIN FLAG-CONTROL-ROOM (NIST AC-3 / CM-5 / AU-2). Flips the three
# Phase-5 enforcement flags for THIS tenant at runtime via the persisted EnforcementSetting overlay.
#
# < AdminController (authenticate_user! + protect_from_forgery with: :exception) and inherits
# ApplicationController's `check_authorization if: :enforce_authorization?` — so under the 5.6 cutover this
# controller is ITSELF subject to the mandatory-auth guard. It AUTHORIZES (never skip_authorization_check):
# `authorize! :manage, EnforcementSetting` in EVERY action (a before_action + an explicit call in #update),
# which admin passes via `can :manage, :all` and every non-admin role is DENIED (CanCan denies by default).
#
# NO-LOCKOUT: because show + update both authorize and admin has :manage, :all, flipping enforce_authorization
# ON keeps THIS page reachable to flip it back OFF; the CanCan::AuthorizationNotPerformed rescue renders a
# STATIC 403 (not redirect_to root_url), so there is no redirect loop even if another controller were
# misconfigured. Escape hatch (documented): `EnforcementSetting.instance.update!(enforce_authorization: nil)`
# in a console reverts to the config.x default (OFF).
class EnforcementSettingsController < AdminController
  # Singleton-per-tenant, NOT a load-by-id resource -> authorize the model CLASS. In-body authorize! is
  # invisible to the hard-CI coverage guard's static scan, so this controller+actions are listed in that
  # spec's IN_BODY_AUTHORIZE allowmap (mirrors access_reviews#index / break_glass_grants#create).
  before_action -> { authorize! :manage, EnforcementSetting }

  def show
    # A GET must NEVER persist a row: use for_display (first || new), NOT instance/first_or_create!, so an
    # all-nil in-memory row is rendered when none exists (resolves identically to absent => config.x OFF).
    @setting = EnforcementSetting.for_display
    load_shadow_summaries
  end

  def update
    authorize! :manage, EnforcementSetting # explicit per-action authorize (defense-in-depth; also the guard's contract)
    @setting = EnforcementSetting.instance # WRITE path: lazily create the row on first flip

    changes = compute_changes(@setting, setting_params)

    @setting.update!(setting_params.merge(updated_by_id: current_user.id))
    EnforcementSetting.clear_cache! # this-request + next-request reads reflect the change promptly

    audit_flag_changes(changes) if changes.any?

    redirect_to enforcement_settings_path,
                notice: t('enforcement_settings.flash.updated', default: 'Enforcement settings saved for this organization.')
  rescue ActiveRecord::RecordInvalid => e
    # A bad value (e.g. lockout below the floor of 3, or an out-of-range timeout) must NOT brick the
    # editing session or auth: re-render the panel with the message and persist NOTHING. @setting holds
    # the rejected in-memory values; the memo is untouched so runtime reads are unaffected.
    flash.now[:alert] = e.record.errors.full_messages.to_sentence
    load_shadow_summaries
    render :show, status: :unprocessable_entity
  end

  private

  # STRONG PARAMS: only the known flags + settings. Blank ('' from the "Use system default" option) => nil
  # (clear the override). Boolean flags cast to true/false. Integer settings: blank => nil; a present but
  # non-numeric string is passed THROUGH unchanged so the model's numericality validation fires and the
  # 422 re-render shows the error (rather than silently clearing the override on a fat-fingered value).
  def setting_params
    keys = EnforcementSetting::FLAGS + EnforcementSetting::BOOL_EXTRA + EnforcementSetting::VALUE_SETTINGS
    permitted = params.require(:enforcement_setting).permit(*keys)
    result = {}
    (EnforcementSetting::FLAGS + EnforcementSetting::BOOL_EXTRA).each do |flag|
      raw = permitted[flag]
      result[flag] = raw.blank? ? nil : ActiveModel::Type::Boolean.new.cast(raw)
    end
    EnforcementSetting::VALUE_SETTINGS.each do |key|
      raw = permitted[key]
      result[key] = raw.blank? ? nil : raw # model numericality validates/casts; non-numeric -> RecordInvalid
    end
    result
  end

  # {key => [old_stored, new_stored]} for only the flags/settings whose stored value actually changed.
  def compute_changes(setting, new_values)
    keys = EnforcementSetting::FLAGS + EnforcementSetting::BOOL_EXTRA + EnforcementSetting::VALUE_SETTINGS
    keys.each_with_object({}) do |key, acc|
      old_stored = setting.public_send(key)
      new_stored = new_values[key]
      acc[key] = [old_stored, new_stored] unless old_stored == new_stored
    end
  end

  # AU-2 security event — coarse metadata (flag name, on/off/default for booleans; numeric from->to for
  # value settings). Numeric policy values (minutes / count / days) are configuration, not PII/secrets, so
  # logging them is acceptable. NEVER any record data. security_event! self-rescues (a Mongo blip never 500s).
  def audit_flag_changes(changes)
    bool_keys = (EnforcementSetting::FLAGS + EnforcementSetting::BOOL_EXTRA)
    AccessLog.security_event!(
      event_type: 'enforcement_flag_changed',
      request: request,
      user: current_user,
      metadata: {
        'changes' => changes.map do |key, (old_v, new_v)|
          if bool_keys.include?(key)
            { 'flag' => key.to_s, 'from' => fmt(old_v), 'to' => fmt(new_v) }
          else
            { 'setting' => key.to_s, 'from' => (old_v.nil? ? 'default' : old_v.to_s), 'to' => (new_v.nil? ? 'default' : new_v.to_s) }
          end
        end,
        'actor_role' => current_user.roles,
        'source' => 'enforcement_settings_ui'
      }
    )
  end

  def fmt(value)
    return 'default(off)' if value.nil?

    value ? 'on' : 'off'
  end

  # INLINE shadow-divergence evidence (the loop-closer): reuse AccessReviewsController's EXACT query logic
  # so the admin sees what WOULD break before flipping. Tenant-isolated by AccessLog default_scope.
  def load_shadow_summaries
    lp_events = AccessLog.where(event_type: 'least_privilege_shadow').order_by(created_at: :desc).limit(200).to_a
    @lp_shadow_summary = lp_events
                         .group_by { |e| [e.user_email, (e.metadata || {})['rule']] }
                         .map { |(email, rule), evs| { email: email, rule: rule, count: evs.size, last_seen: evs.first.created_at } }
                         .sort_by { |row| [-row[:count], row[:email].to_s] }

    authz_events = AccessLog.where(event_type: 'authorization_shadow').order_by(created_at: :desc).limit(200).to_a
    @authz_shadow_summary = authz_events
                            .group_by { |e| m = e.metadata || {}; [m['controller'], m['action'], m['role']] }
                            .map { |(controller, action, role), evs| { controller: controller, action: action, role: role, count: evs.size, last_seen: evs.first.created_at } }
                            .sort_by { |row| [-row[:count], row[:controller].to_s, row[:action].to_s] }

    @tenant_mismatch_count = AccessLog.where(event_type: 'tenant_mismatch').count
  end
end
