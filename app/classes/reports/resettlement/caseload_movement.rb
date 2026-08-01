# frozen_string_literal: true

module Reports
  module Resettlement
    # Caseload Movement — the RS-51 / ORR-6 Schedule B shape, per program:
    # active at period start / new enrollments / exits / active at period end,
    # counted as PERSONS and as HOUSEHOLDS. Pure SQL (exit_date is plaintext).
    # start + new − exits = end holds when statuses are consistent; the report
    # shows the actual end-state count rather than forcing the algebra.
    class CaseloadMovement < BaseReport
      private

      def build_sections
        rows = ProgramStream.order(:name).map do |program|
          start_ids = active_at(program.id, period.start_date - 1)
          new_ids = scoped_enrollments([program.id])
                    .where(enrollment_date: period.range).pluck(:client_id).uniq
          exit_ids = scoped_enrollments([program.id])
                     .joins(:leave_program)
                     .where(leave_programs: { exit_date: period.range })
                     .pluck(:client_id).uniq
          end_ids = active_at(program.id, period.end_date)
          [program.name,
           start_ids.size, household_count(start_ids),
           new_ids.size, exit_ids.size,
           end_ids.size, household_count(end_ids)]
        end

        [Section.new(key: :movement, columns: cols, rows: rows,
                     footnote: I18n.t('reports.registry.caseload_movement.footnote'))]
      end

      # Active at a date: enrolled on/before it, and either never exited or
      # exited strictly after it.
      def active_at(program_id, date)
        scoped_enrollments([program_id])
          .where(enrollment_date: ..date)
          .left_joins(:leave_program)
          .where('leave_programs.id IS NULL OR leave_programs.exit_date > ?', date)
          .pluck(:client_id).uniq
      end

      def cols
        %w[program start_individuals start_households new exits end_individuals end_households].map do |key|
          I18n.t("reports.registry.caseload_movement.columns.#{key}")
        end
      end
    end
  end
end
