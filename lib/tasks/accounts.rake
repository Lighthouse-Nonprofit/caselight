# lib/tasks/accounts.rake
#
# Phase 6 — AC-2(3) automatic disabling of inactive accounts. Dormant credentials are standing
# attack surface; nothing disabled them before (the `disable` flag was manual-only).
#
# Per-tenant threshold: EnforcementSetting#inactive_disable_days (panel-editable, 30-day floor).
#   NULL  => REPORT-ONLY: print what a hypothetical 90-day policy would flag, disable nobody
#            (the shadow default — safe to schedule daily from day one).
#   set   => accounts idle longer than N days are disabled (user.disable = true; reversible from
#            the user page; :lockable/:timeoutable/history untouched).
#
# Candidate = not already disabled AND max(current_sign_in_at, last_sign_in_at, created_at) older
# than the threshold (created_at fallback so a never-signed-in account ages out too).
#
# LAST-ADMIN GUARD: never disables a user when doing so would leave the tenant with ZERO enabled
# admins (same brick-prevention philosophy as the lockout floor). The skip is logged.
#
# Safety posture mirrors audit.rake: DRY-RUN unless CONFIRM=1 (a double gate on top of the nil =>
# report-only default). Each disable writes a values-free `account_disabled` AccessLog row (AU-2).

namespace :accounts do
  REPORT_ONLY_WINDOW_DAYS = 90

  def stale_users(days)
    cutoff = days.days.ago
    User.where(disable: [false, nil]).select do |u|
      [u.current_sign_in_at, u.last_sign_in_at, u.created_at].compact.max < cutoff
    end
  end

  desc "Disable accounts inactive beyond each tenant's inactive_disable_days (nil => report-only). " \
       "DRY-RUN unless CONFIRM=1. e.g. CONFIRM=1 rake accounts:disable_inactive"
  task disable_inactive: :environment do
    confirm = ENV["CONFIRM"] == "1"

    Organization.pluck(:short_name).sort.each do |tenant|
      Apartment::Tenant.switch(tenant) do
        threshold = EnforcementSetting.effective_value(
          :inactive_disable_days,
          config_default: EnforcementSetting.config_default_for_value(:inactive_disable_days)
        )

        if threshold.blank?
          # REPORT-ONLY shadow: size a hypothetical 90d policy so the admin can pick a threshold
          # from evidence before turning the feature on. Nothing is disabled.
          puts "[accounts:disable_inactive] tenant=#{tenant} threshold=OFF (report-only) " \
               "would_flag_at_#{REPORT_ONLY_WINDOW_DAYS}d=#{stale_users(REPORT_ONLY_WINDOW_DAYS).size}"
          next
        end

        candidates = stale_users(threshold)
        puts "[accounts:disable_inactive] tenant=#{tenant} threshold=#{threshold}d candidates=#{candidates.size} confirm=#{confirm}"
        next if candidates.empty?

        candidates.each do |user|
          # LAST-ADMIN GUARD (re-checked per disable, so a batch can never drain the admin pool):
          # skip when no OTHER enabled admin would remain.
          if user.roles == 'admin' &&
             User.where(roles: 'admin').where(disable: [false, nil]).where.not(id: user.id).none?
            puts "  SKIP user_id=#{user.id} (last enabled admin — never auto-disabled)"
            next
          end

          unless confirm
            puts "  DRY-RUN would disable user_id=#{user.id} roles=#{user.roles}"
            next
          end

          user.update!(disable: true)
          AccessLog.system_event!(
            event_type: 'account_disabled',
            user:       user,
            metadata:   { 'reason' => 'inactivity', 'threshold_days' => threshold, 'task' => 'accounts:disable_inactive' }
          )
          puts "  DISABLED user_id=#{user.id} roles=#{user.roles}"
        end
      end
    end
  end
end
