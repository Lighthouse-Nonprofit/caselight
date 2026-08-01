# Youth-flavor batch Y2(c) — the minimum interval between a client's assessments.
# UNSET (the default) preserves the legacy CALENDAR arithmetic exactly: 6.months —
# which is NOT 180.days (calendar months vary; swapping units would silently shift
# every existing due date by ±3 days). Set ASSESSMENT_MIN_INTERVAL_DAYS to an integer
# to switch to precise day arithmetic — youth boxes use 84 (12-week SEL pre/post
# cohort cadence). Feeds BOTH the creation gate (Client#can_create_assessment?) and
# the due/overdue notification clock — don't set 0, or every assessed client reads
# as overdue the next day.
raw = ENV['ASSESSMENT_MIN_INTERVAL_DAYS'].presence
Rails.application.config.x.assessment_min_interval_days = raw ? Integer(raw) : nil
