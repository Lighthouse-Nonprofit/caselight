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
        enrollments = roster(program).to_a
        session_tracking = program.trackings.find_by(name: SESSION_TRACKING)

        # ONE sidecar query for the whole cohort (was one per enrollment — an
        # N+1 that scaled with the roster), tallied per enrollment in Ruby.
        present_by_enrollment = present_counts(enrollments, session_tracking)
        completers = 0
        rows = enrollments.map do |enrollment|
          present = present_by_enrollment.fetch(enrollment.id, 0)
          completer = present >= threshold
          completers += 1 if completer
          [client_label(enrollment.client), present, total_sessions,
           completer ? I18n.t('reports.registry.cohort_completion.completer') : '']
        end

        rate = enrollments.empty? ? '—' : "#{(100.0 * completers / enrollments.size).round}%"
        footnote = I18n.t('reports.registry.cohort_completion.footnote',
                          program: program.name, term: period.term_label || period.label,
                          threshold: threshold, total: total_sessions, rate: rate)
        if fallback_programs.include?(program.name)
          footnote += " #{I18n.t('reports.registry.cohort_completion.all_terms_note')}"
        end
        Section.new(
          key: :"cohort_#{program.name.parameterize.underscore}",
          title: program.name,
          columns: cols,
          rows: rows,
          footnote: footnote
        )
      end

      # { enrollment_id => Present count } in one indexed sidecar query.
      def present_counts(enrollments, session_tracking)
        return {} if enrollments.empty? || session_tracking.nil?
        entries = ClientEnrollmentTracking.where(client_enrollment_id: enrollments.map(&:id),
                                                 tracking_id: session_tracking.id)
        present_ids = Reports::ValueCounts.owner_ids(owner_scope: entries,
                                                     field_label: 'Attendance', value: 'Present')
        ClientEnrollmentTracking.where(id: present_ids)
                                .group(:client_enrollment_id).count
      end

      # Roster for the period's term. If NO enrollment carries that Term value
      # (imported enrollments have no properties at all, so no sidecar rows),
      # fall back to all terms — the same posture the school hub's cohort cards
      # take, so the two surfaces can never disagree. `fallback?` footnotes it.
      def roster(program)
        scope = scoped_enrollments([program.id]).includes(:client)
        return scope.where(enrollment_date: ..period.end_date) unless period.term_label
        ids = Reports::ValueCounts.owner_ids(owner_scope: scope,
                                             field_label: 'Term',
                                             value: period.term_label)
        if ids.empty?
          fallback_programs << program.name
          scope.where(enrollment_date: ..period.end_date)
        else
          scope.where(id: ids)
        end
      end

      def fallback_programs
        @fallback_programs ||= []
      end

      def cols
        %w[youth present total completer].map do |key|
          I18n.t("reports.registry.cohort_completion.columns.#{key}")
        end
      end
    end
  end
end
