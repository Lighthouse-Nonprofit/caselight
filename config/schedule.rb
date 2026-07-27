# The pilot box runs the app INSIDE Docker Compose and installs this crontab on the HOST
# (bootstrap.sh: `docker compose run --rm app bundle exec whenever | crontab -`), so every job
# shells into the app container. RAILS_ENV is baked into the container env. Output redirections
# resolve after the `cd`, so relative log paths land under /home/ubuntu/oscar/log/.
set :output, 'log/cron.log'
job_type :rake,   'cd /home/ubuntu/oscar && docker compose exec -T app bundle exec rake :task --silent :output'
job_type :runner, %q(cd /home/ubuntu/oscar && docker compose exec -T app bundle exec rails runner ':task' :output)

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
# admin sets inactive_disable_days in the enforcement panel. Disabling is reversible.
every :day, at: '01:00 am' do
  rake 'accounts:disable_inactive CONFIRM=1', output: 'log/whenever.log'
end

every :month, at: '00:00 am' do
  rake 'ngo_usage_report:generate', output: 'log/whenever.log'
  rake 'staff_monthly_report:generate', output: 'log/whenever.log'
end

# POAM-015 (closed) — archive-gated retention, now SCHEDULED. Weekly order matters:
# archive (02:00) -> verify (02:30) -> purges (03:00). A purge whose window has no VERIFIED archive
# REFUSES in code, so a failed archive/verify simply skips that week's purge — fail-safe.
# Windows: access_logs 90d online (AU-11, ratified); versions + Mongo histories 1095d
# (3 years — ratified 2026-07-26, policies/data-retention.md §2).
every :sunday, at: '02:00 am' do
  rake 'retention:archive AUDIT_DAYS=90 DAYS=1095'
end

every :sunday, at: '02:30 am' do
  rake 'retention:verify_archive'
end

every :sunday, at: '03:00 am' do
  rake 'audit:purge DAYS=90 CONFIRM=1'
  rake 'retention:purge_versions DAYS=1095 CONFIRM=1'
  rake 'retention:purge_client_histories DAYS=1095 CONFIRM=1'
end
