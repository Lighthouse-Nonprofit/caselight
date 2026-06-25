# frozen_string_literal: true

# Phase-3 access-logging toggle. FedRAMP AU-2/AU-12 read-logging is ON by default;
# this flag exists only as an operational kill switch (e.g. if read-volume logging
# ever needs to be paused) and mirrors the config.x.enforce_mfa_for_privileged
# pattern in config/initializers/two_factor.rb.
#
# Default TRUE: auditing access is a control requirement, so it must be opt-OUT,
# never opt-in. Set ACCESS_LOGGING_ENABLED=false to disable. NOTE: this flag
# governs ONLY read-access logging (event_type "read"); security events
# (login_failure / account_locked / access_denied) are ALWAYS recorded and are not
# subject to this toggle. The AccessAudit concern also fails safe: if this
# initializer is ever dropped, read-logging stays ON (only an explicit false disables).
Rails.application.config.x.access_logging_enabled =
  ActiveModel::Type::Boolean.new.cast(ENV.fetch("ACCESS_LOGGING_ENABLED", true))
