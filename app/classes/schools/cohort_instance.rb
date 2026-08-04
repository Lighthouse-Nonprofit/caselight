# frozen_string_literal: true

module Schools
  # S4 — a cohort INSTANCE is a curriculum running at ONE school for ONE term
  # (program × school × term). It is made of SESSIONS (1..total, each held on a
  # date) and attended by a ROSTER. This class lays both out explicitly instead
  # of leaving them implied by a pile of tracking entries.
  #
  # One bounded decrypt pass over the instance's session entries
  # (roster × sessions ≈ 25 × 13) builds every number below.
  class CohortInstance
    Session = Struct.new(:number, :date, :present, :absent, :excused, keyword_init: true) do
      def held? = !date.nil?
      def logged = present.to_i + absent.to_i + excused.to_i
      def attendance_pct
        return nil if logged.zero?
        (100.0 * present.to_i / logged).round
      end
    end

    RosterRow = Struct.new(:client, :enrollment, :present, :absent, :excused, :completer,
                           keyword_init: true) do
      def completer? = !!completer
    end

    attr_reader :program, :school, :term_label

    def initialize(program:, school:, enrollments:, term_label:)
      @program = program
      @school = school
      @enrollments = enrollments.to_a
      @term_label = term_label
    end

    def total_sessions = Cohorts.total_sessions(@program.name)
    def completer_threshold = Cohorts.completer_threshold(@program.name)
    def enrolled = @enrollments.size
    def completers = roster.count(&:completer?)
    def sessions_held = sessions.count(&:held?)

    def next_session_number
      (sessions.find { |session| !session.held? } || sessions.last)&.number
    end

    # Sessions 1..total — every slot renders, held or not (an unheld session is a
    # session that still needs a roll call, not a missing row).
    def sessions
      @sessions ||= begin
        by_number = scan[:by_number]
        (1..total_sessions).map do |number|
          data = by_number[number.to_s] || {}
          Session.new(number: number, date: data[:date], present: data[:present].to_i,
                      absent: data[:absent].to_i, excused: data[:excused].to_i)
        end
      end
    end

    # Any entries whose Session Number is missing or outside 1..total (hand-entered
    # or imported) — surfaced so they are never silently dropped.
    def unnumbered_entries = scan[:unnumbered]

    def roster
      @roster ||= @enrollments.map do |enrollment|
        counts = scan[:by_enrollment][enrollment.id] || {}
        present = counts[:present].to_i
        RosterRow.new(client: enrollment.client, enrollment: enrollment, present: present,
                      absent: counts[:absent].to_i, excused: counts[:excused].to_i,
                      completer: present >= completer_threshold)
      end.sort_by { |row| row.client.name.to_s }
    end

    private

    def tracking
      @tracking ||= @program.trackings.find_by(name: Cohorts::SESSION_TRACKING)
    end

    # ONE decrypt pass → per-session-number tallies, per-enrollment tallies, and
    # the count of entries that carry no usable session number.
    def scan
      @scan ||= begin
        by_number = {}
        by_enrollment = {}
        unnumbered = 0
        if tracking && @enrollments.any?
          scope = ClientEnrollmentTracking.where(client_enrollment_id: @enrollments.map(&:id),
                                                 tracking_id: tracking.id)
          Reports::DecryptedScan.each(scope) do |record, props|
            state = props['Attendance'].to_s.downcase
            key = %w[present absent excused].include?(state) ? state.to_sym : nil
            number = props['Session Number'].to_s
            if number.present? && (1..total_sessions).cover?(number.to_i)
              bucket = (by_number[number] ||= { date: nil, present: 0, absent: 0, excused: 0 })
              bucket[:date] ||= record.entry_date
              bucket[:date] = record.entry_date if record.entry_date && bucket[:date] > record.entry_date
              bucket[key] += 1 if key
            else
              unnumbered += 1
            end
            if key
              per = (by_enrollment[record.client_enrollment_id] ||= { present: 0, absent: 0, excused: 0 })
              per[key] += 1
            end
          end
        end
        { by_number: by_number, by_enrollment: by_enrollment, unnumbered: unnumbered }
      end
    end
  end
end
