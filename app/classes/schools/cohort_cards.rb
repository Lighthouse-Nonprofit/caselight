# frozen_string_literal: true

module Schools
  # HUB1 — one card per cohort curriculum with members at this school. The
  # roster is the CURRENT term's (sidecar Term probe); when a program has
  # school members but none in the current term, the card falls back to all
  # terms and says so (demo data seeds Spring-26 terms — the fallback note is
  # the expected state there). Math = Cohorts (shared with the report).
  class CohortCards
    Card = Struct.new(:program, :term_label, :enrolled, :sessions_logged,
                      :avg_attendance_pct, :completers, :fallback, keyword_init: true) do
      def fallback? = !!fallback
    end

    def initialize(youth_ids:)
      @youth_ids = Array(youth_ids)
      @term_label = Reports::Period.current(:term).term_label
    end

    attr_reader :term_label

    def cards
      @cards ||= Cohorts.programs.filter_map { |program| card_for(program) }
    end

    # The (ability-scoped) enrollments a roll call addresses — current term,
    # with the same all-terms fallback as the cards. Used by HUB2.
    def roster_for(program)
      scope = school_enrollments(program)
      term_ids = Reports::ValueCounts.owner_ids(owner_scope: scope,
                                                field_label: 'Term', value: @term_label)
      roster = term_ids.any? ? scope.where(id: term_ids) : scope
      roster.includes(:client).sort_by { |e| e.client.name.to_s }
    end

    private

    def school_enrollments(program)
      ClientEnrollment.where(client_id: @youth_ids, program_stream_id: program.id)
    end

    def card_for(program)
      scope = school_enrollments(program)
      return nil if scope.none?

      term_ids = Reports::ValueCounts.owner_ids(owner_scope: scope,
                                                field_label: 'Term', value: @term_label)
      fallback = term_ids.empty?
      roster = fallback ? scope : scope.where(id: term_ids)

      tracking = program.trackings.find_by(name: Cohorts::SESSION_TRACKING)
      entries = ClientEnrollmentTracking.where(client_enrollment_id: roster.select(:id),
                                               tracking_id: tracking&.id)
      logged = entries.count
      threshold = Cohorts.completer_threshold(program.name)
      # ONE sidecar query for the cohort (was one per enrollment — this runs on
      # EVERY school page via set_hub, so the N+1 scaled with the roster).
      present_ids = logged.zero? ? [] : Reports::ValueCounts.owner_ids(
        owner_scope: entries, field_label: 'Attendance', value: 'Present'
      )
      present = present_ids.size
      per_enrollment = ClientEnrollmentTracking.where(id: present_ids)
                                               .group(:client_enrollment_id).count
      completers = per_enrollment.count { |_id, count| count >= threshold }

      Card.new(program: program, term_label: fallback ? nil : @term_label,
               enrolled: roster.count, sessions_logged: logged,
               avg_attendance_pct: logged.zero? ? nil : (100.0 * present / logged).round,
               completers: completers, fallback: fallback)
    end
  end
end
