# frozen_string_literal: true
require 'rails_helper'
require 'whenever'

# Scheduler (cron) regression spec — asserts config/schedule.rb declares the recurring jobs the app
# depends on, at the right frequency and time.
#
# WHY THIS WAS REWRITTEN (whenever 0.9.7 -> 1.1.2; Dependabot follow-up):
# The original spec used the `shoulda-whenever` (~> 0.0.2) matcher:
#   include Shoulda::Whenever
#   expect(whenever).to schedule('users:remind').every(:monday).at('00:00 am')
# `shoulda-whenever` was written against whenever ~0.x, where `Whenever::JobList`'s internal `@jobs`
# was a SINGLE-level hash keyed by time scope: @jobs[:day] = [Job, ...]. whenever 1.1.x added a
# per-MAILTO layer, so `@jobs` is now TWO levels: @jobs[:default_mailto][:day] = [Job, ...]. The
# matcher's `filter_jobs_by_duration` calls `jobs.fetch(:day)` on the TOP-LEVEL hash — whose only key
# is now `:default_mailto`, not `:day` — so it always returns `[]` and every example goes RED (5/5).
# shoulda-whenever 0.0.2 has had no release since and does not know about the mailto layer; there is
# no version of it compatible with whenever 1.1.x.
#
# Rather than loosen the assertions, we assert the SAME jobs DIRECTLY against the Whenever API: parse
# config/schedule.rb with `Whenever::JobList` (exactly how `whenever`/`crontab` parse it at deploy
# time), flatten the two-level `@jobs` structure, and assert a job exists with the expected task string,
# time scope (`every`) AND time (`at`). The negative guard proves the assertion is still specific (a
# real task at the wrong frequency/time does NOT match), so the rewrite is strictly no weaker than the
# matcher it replaces. `shoulda-whenever` is no longer referenced and can be dropped in a cleanup pass.
#
# This spec is encryption/Phase-4-independent (config/schedule.rb contains no PII); it ships in the
# Phase-4 close-out only because fixing it unblocks adding schedule_spec.rb to CI. It is added to the
# `RSpec (non-feature suite)` step in .github/workflows/ci.yml (that step lists explicit directories and
# does NOT pick up top-level specs). The spec needs no DB rows and no tenant switch — it only reads
# config/schedule.rb — so it is safe to append to the existing command.
RSpec.describe 'Scheduler (config/schedule.rb cron jobs)' do
  # Parse the real schedule the same way `whenever` does when it writes the crontab.
  let(:job_list) { Whenever::JobList.new(file: Rails.root.join('config', 'schedule.rb').to_s) }

  # whenever 1.1.x stores @jobs as { mailto => { time_scope => [Job, ...] } }. Flatten to the flat list
  # of jobs for a given time scope (:day, :monday, :month, ...) across all mailto buckets.
  def jobs_every(scope)
    by_mailto = job_list.instance_variable_get(:@jobs)
    by_mailto.values.flat_map { |by_scope| by_scope.fetch(scope, []) }
  end

  # A Whenever::Job keeps its task string in @options[:task] (not deleted in the initializer, unlike
  # :at/:mailto/:roles/etc.) and exposes its time via the public `#at` reader.
  def scheduled?(task:, every:, at:)
    jobs_every(every).any? do |job|
      job.instance_variable_get(:@options)[:task] == task && job.at == at
    end
  end

  describe 'A Reminder Email' do
    it 'sends caseworkers their incomplete upcoming tasks every day at 00:00 am' do
      expect(scheduled?(task: 'Task.upcoming_incomplete_tasks', every: :day, at: '00:00 am')).to be true
    end
  end

  describe 'Reminder exit EC on day 83' do
    it 'runs Client.ec_reminder_in(83) every day at 00:00 am' do
      expect(scheduled?(task: 'Client.ec_reminder_in(83)', every: :day, at: '00:00 am')).to be true
    end
  end

  describe 'Reminder exit EC on day 90' do
    it 'runs Client.ec_reminder_in(90) every day at 00:00 am' do
      expect(scheduled?(task: 'Client.ec_reminder_in(90)', every: :day, at: '00:00 am')).to be true
    end
  end

  describe 'Overdue tasks reminding email' do
    it 'runs the users:remind rake task every Monday at 00:00 am' do
      expect(scheduled?(task: 'users:remind', every: :monday, at: '00:00 am')).to be true
    end
  end

  describe 'Cambodian Families Usage Report' do
    it 'runs the ngo_usage_report:generate rake task every month at 00:00 am' do
      expect(scheduled?(task: 'ngo_usage_report:generate', every: :month, at: '00:00 am')).to be true
    end
  end

  # Specificity guard: a real task asserted at the WRONG frequency or WRONG time must NOT match — this
  # keeps the rewrite as strict as the old `.every(...).at(...)` matcher chain.
  describe 'guard: the assertion is specific (wrong frequency / time do not match)' do
    it 'does not match a real task at the wrong frequency or the wrong time' do
      expect(scheduled?(task: 'users:remind', every: :day,    at: '00:00 am')).to be false
      expect(scheduled?(task: 'users:remind', every: :monday, at: '03:00 am')).to be false
    end
  end
end
