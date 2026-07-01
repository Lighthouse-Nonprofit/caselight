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

    changes = compute_changes(@setting, flag_params)

    @setting.update!(flag_params.merge(updated_by_id: current_user.id))
    EnforcementSetting.clear_cache! # this-request + next-request reads reflect the flip promptly

    audit_flag_changes(changes) if changes.any?

    redirect_to enforcement_settings_path,
                notice: t('enforcement_settings.flash.updated', default: 'Enforcement settings saved for this organization.')
  end

  private

  # STRONG PARAMS: only the three known flags, nothing else can be written through this controller. Blank
  # ('' from the "Use system default" option) -> nil (clear override); 'true'/'false' -> boolean.
  def flag_params
    permitted = params.require(:enforcement_setting).permit(*EnforcementSetting::FLAGS)
    EnforcementSetting::FLAGS.index_with do |flag|
      raw = permitted[flag]
      raw.blank? ? nil : ActiveModel::Type::Boolean.new.cast(raw)
    end
  end

  # {flag => [old_stored, new_stored]} for only the flags whose stored value actually changed.
  def compute_changes(setting, new_values)
    EnforcementSetting::FLAGS.each_with_object({}) do |flag, acc|
      old_stored = setting.public_send(flag)
      new_stored = new_values[flag]
      acc[flag] = [old_stored, new_stored] unless old_stored == new_stored
    end
  end

  # AU-2 security event: ONE row carrying the diff for the request. CONTEXT-ONLY metadata (flag name,
  # old->new state, actor role) — NEVER any record data. security_event! self-rescues (a Mongo blip never
  # 500s the flip); the PG row + updated_by_id/updated_at remain the authoritative change record.
  def audit_flag_changes(changes)
    AccessLog.security_event!(
      event_type: 'enforcement_flag_changed',
      request: request,
      user: current_user,
      metadata: {
        'changes' => changes.map { |flag, (old_v, new_v)| { 'flag' => flag.to_s, 'from' => fmt(old_v), 'to' => fmt(new_v) } },
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
