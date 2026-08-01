# frozen_string_literal: true

# HUB1 — the cohort-curriculum math, extracted so the Cohort Completion report,
# the school hub's cohort cards, and the roll-call surface share ONE source of
# truth (Reports::Youth::CohortCompletion delegates here; its behavior is
# frozen by spec/lib/reports/youth_leadership_spec.rb).
module Cohorts
  SESSION_TRACKING = 'Session Attendance'
  # Per-curriculum session totals (OCA-confirmable; NCN's Jovenes con Palabra
  # runs 12 weekly circles, Girasol 13). Completer = 75% of the total.
  SESSION_TOTALS = { 'El Joven Noble' => 12, 'Girasol' => 13 }.freeze
  DEFAULT_SESSIONS = 12
  COMPLETER_RATIO = 0.75

  def self.total_sessions(program_name)
    SESSION_TOTALS.fetch(program_name, DEFAULT_SESSIONS)
  end

  def self.completer_threshold(program_name)
    (total_sessions(program_name) * COMPLETER_RATIO).ceil
  end

  # Every program carrying the session tracking = the cohort curricula.
  def self.programs
    ProgramStream.joins(:trackings)
                 .where(trackings: { name: SESSION_TRACKING })
                 .order(:name).distinct
  end

  # Present count over a ClientEnrollmentTracking scope — sidecar equality,
  # never a ciphertext scan.
  def self.present_count(entry_scope)
    Reports::ValueCounts.owner_ids(owner_scope: entry_scope,
                                   field_label: 'Attendance', value: 'Present').size
  end
end
