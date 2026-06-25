# frozen_string_literal: true

# AccessAudit — records WHO-VIEWED-WHAT-WHEN-WHERE for sensitive resources.
# FedRAMP AU-2/AU-12. Included ONLY in the sensitive resource controllers
# (clients / progress_notes / assessments / case_notes), NOT in AdminController —
# auditing every admin chrome page would bury the signal and over-collect.
#
# Design notes:
# - after_action on show + index only. show = a single-record read; index = a
#   collection read (AU-2 says "access", which includes browsing the list).
# - Guarded: only fires when there is a current_user AND the response was a 2xx.
#   We do NOT audit failed/redirected/forbidden reads here — access_denied is its
#   own security event at the rescue seam.
# - resource_type/resource_id are derived inside AccessLog.record_read! from
#   controller_name + params[:id], so this concern does NOT depend on a specific
#   ivar name across the four controllers.
# - Resilience: record_read! already rescues internally, but we also guard the
#   call site so nothing here can ever break the request being audited.
module AccessAudit
  extend ActiveSupport::Concern

  included do
    after_action :record_access_read, only: %i[show index]
  end

  private

  def record_access_read
    # Phase-3 kill switch (mirrors config/initializers/two_factor.rb flag pattern).
    # FAIL-SAFE: only an EXPLICIT false disables read-logging. config.x is an
    # ActiveSupport::OrderedOptions, so a missing initializer yields nil (not an
    # error) -> nil must keep logging ON, because an audit control fails SAFE
    # (opt-OUT, never opt-in). This governs ONLY read logging; security events
    # (login_failure/account_locked/access_denied) are always recorded.
    return if Rails.application.config.x.access_logging_enabled == false
    return unless current_user
    return unless response.successful? # 2xx only

    AccessLog.record_read!(self)
  rescue => e
    # Belt-and-suspenders: never let auditing break the audited request.
    Rails.logger.error("[AccessAudit] record_access_read failed: #{e.class}: #{e.message}")
    nil
  end
end
