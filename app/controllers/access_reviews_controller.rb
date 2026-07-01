# frozen_string_literal: true
# AccessReviewsController - AC-2(j) periodic access recertification (SOC 2 CC6.2/CC6.3).
# Point-in-time "who has what role / last login / MFA on" for the CURRENT tenant. This is
# Postgres point-in-time STATE, not the AccessLog event trail. PER-TENANT: run once per
# subdomain (iterate Organization.pluck(:short_name)) to recertify all staff.
class AccessReviewsController < AdminController
  def index
    authorize! :read, :access_review # admin-only via `can :manage, :all`; also satisfies verify_authorized at the 5.6 cutover

    @users = User.includes(:department)
                 .to_a
                 .sort_by { |u| u.name.to_s.downcase } # name is deterministically encrypted (Tier 3) -> sort in memory, never ORDER BY

    # Phase 5.5 (AC-6) shadow window: surface how often each staff member's access WOULD have been
    # denied by the narrowed rules before the org flips config.x.enforce_least_privilege. Pure
    # AccessLog context (counts + rule), no record values. Tenant-isolated by AccessLog default_scope.
    @lp_shadow_events  = AccessLog.where(event_type: 'least_privilege_shadow')
                                  .order_by(created_at: :desc).limit(200).to_a
    @lp_shadow_summary = @lp_shadow_events
                         .group_by { |e| [e.user_email, (e.metadata || {})['rule']] }
                         .map { |(email, rule), evs| { email: email, rule: rule, count: evs.size, last_seen: evs.first.created_at } }
                         .sort_by { |row| [-row[:count], row[:email].to_s] }

    # Phase 5.6 (AC-3) cutover shadow window: surface which (controller, action, role) tuples WOULD fail
    # the mandatory-authorization check before the org flips config.x.enforce_authorization. Pure AccessLog
    # context (controller/action/role), no record values. The operator's is-the-allowlist-complete view.
    @authz_shadow_events  = AccessLog.where(event_type: 'authorization_shadow')
                                     .order_by(created_at: :desc).limit(200).to_a
    @authz_shadow_summary = @authz_shadow_events
                            .group_by { |e| m = e.metadata || {}; [m['controller'], m['action'], m['role']] }
                            .map { |(controller, action, role), evs| { controller: controller, action: action, role: role, count: evs.size, last_seen: evs.first.created_at } }
                            .sort_by { |row| [-row[:count], row[:controller].to_s, row[:action].to_s] }

    respond_to do |format|
      format.html
      format.csv do
        send_data access_review_csv(@users),
                  filename: "access_review_#{Organization.current.try(:short_name)}_#{Date.current.iso8601}.csv",
                  type: 'text/csv'
      end
    end
  end

  private

  def access_review_csv(users)
    require 'csv'
    CSV.generate(headers: true) do |csv|
      csv << ['User ID', 'Name', 'Email', 'Role', 'Manager ID', 'Last Sign In', 'Current Sign In',
              'Sign In Count', 'MFA Enabled', 'MFA Gap (privileged w/o MFA)', 'Passkeys',
              'Locked', 'Failed Attempts', 'Disabled', 'Created']
      users.each do |u|
        mfa_gap = u.mfa_privileged? && !u.two_factor_enabled?
        csv << [u.id, u.name, u.email, u.roles, u.manager_id,
                u.last_sign_in_at&.iso8601, u.current_sign_in_at&.iso8601, u.sign_in_count,
                (u.two_factor_enabled? ? 'yes' : 'no'), (mfa_gap ? 'YES' : 'no'),
                u.webauthn_credentials.size,
                (u.respond_to?(:access_locked?) && u.access_locked? ? 'yes' : 'no'),
                u.failed_attempts, (u.disable? ? 'yes' : 'no'), u.created_at&.iso8601]
      end
    end
  end
end
