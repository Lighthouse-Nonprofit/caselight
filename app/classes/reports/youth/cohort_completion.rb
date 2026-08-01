# frozen_string_literal: true

module Reports
  module Youth
    # Cohort Completion — the native shape of the cultura curricula: roster per
    # curriculum × Term (via sidecar equality on the enrollment's Term field),
    # per-youth sessions attended / sessions logged, completer at >= 75% of the
    # curriculum's session total (Joven Noble 12, Girasol 13, default 12 —
    # OCA-confirmable constants), and the cohort completion rate.
    class CohortCompletion < BaseReport
      # HUB1: the math lives in Cohorts (shared with the school hub + roll call);
      # these aliases keep this report's public constants stable.
      SESSION_TRACKING = Cohorts::SESSION_TRACKING
      SESSION_TOTALS = Cohorts::SESSION_TOTALS
      DEFAULT_SESSIONS = Cohorts::DEFAULT_SESSIONS
      COMPLETER_RATIO = Cohorts::COMPLETER_RATIO

      private

      def build_sections
        cohort_programs.map { |program| cohort_section(program) }
      end

      def cohort_programs
        ProgramStream.joins(:trackings)
                     .where(trackings: { name: SESSION_TRACKING })
                     .order(:name).distinct
      end

      def cohort_section(program)
        total_sessions = SESSION_TOTALS.fetch(program.name, DEFAULT_SESSIONS)
        threshold = (total_sessions * COMPLETER_RATIO).ceil
        enrollments = roster(program)
        session_tracking = program.trackings.find_by(name: SESSION_TRACKING)

        completers = 0
        rows = enrollments.map do |enrollment|
          entries = ClientEnrollmentTracking.where(client_enrollment_id: enrollment.id,
                                                   tracking_id: session_tracking.id)
          present = Reports::ValueCounts.owner_ids(owner_scope: entries,
                                                   field_label: 'Attendance',
                                                   value: 'Present').size
          completer = present >= threshold
          completers += 1 if completer
          [client_label(enrollment.client), present, total_sessions,
           completer ? I18n.t('reports.registry.cohort_completion.completer') : '']
        end

        rate = enrollments.empty? ? '—' : "#{(100.0 * completers / enrollments.size).round}%"
        Section.new(
          key: :"cohort_#{program.name.parameterize.underscore}",
          columns: cols,
          rows: rows,
          footnote: I18n.t('reports.registry.cohort_completion.footnote',
                           program: program.name, term: period.term_label || period.label,
                           threshold: threshold, total: total_sessions, rate: rate)
        )
      end

      # Roster: enrollments in the program whose Term field matches the period's
      # term label (sidecar equality); a non-term period falls back to
      # enrollments active in the period.
      def roster(program)
        scope = scoped_enrollments([program.id]).includes(:client)
        if period.term_label
          ids = Reports::ValueCounts.owner_ids(owner_scope: scope,
                                               field_label: 'Term',
                                               value: period.term_label)
          scope.where(id: ids)
        else
          scope.where(enrollment_date: ..period.end_date)
        end
      end

      def cols
        %w[youth present total completer].map do |key|
          I18n.t("reports.registry.cohort_completion.columns.#{key}")
        end
      end
    end
  end
end
