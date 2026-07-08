every :day, :at => '00:00 am' do
  runner 'Task.upcoming_incomplete_tasks', output: 'log/whenever.log'
  runner 'Client.ec_reminder_in(83)', output: 'log/whenever.log'
  runner 'Client.ec_reminder_in(90)', output: 'log/whenever.log'
end

every :monday, at: '00:00 am' do
  rake 'users:remind'
end

# Phase 6 — AC-2(3) inactive-account lifecycle. Safe to schedule from day one: with the per-tenant
# threshold unset (the default) the run is REPORT-ONLY and disables nobody; it only enforces once an
# admin sets inactive_disable_days in the enforcement panel. Disabling is reversible — unlike the
# retention purges, which stay deliberately UNscheduled (archive-verification gate POA&M).
every :day, at: '01:00 am' do
  rake 'accounts:disable_inactive CONFIRM=1', output: 'log/whenever.log'
end

every :month, at: '00:00 am' do
  rake 'ngo_usage_report:generate', output: 'log/whenever.log'
  rake 'staff_monthly_report:generate', output: 'log/whenever.log'
end
