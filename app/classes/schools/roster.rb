# frozen_string_literal: true

module Schools
  # HUB1 — the school roster rows: per (ability-scoped) youth, their programs,
  # last service contact, and an academic glance from the LATEST Aeries entry
  # only. Decrypt volume is bounded by construction: a DISTINCT ON id-list
  # first (one row per PV enrollment), then one DecryptedScan pass over just
  # those ids — never full history.
  class Roster
    AERIES_PROGRAM = '¡Por Vida!'
    AERIES_TRACKING = 'Academic Check-in (Aeries)'
    GPA_LABEL = 'GPA (x100, e.g. 275 = 2.75)'
    ATTENDANCE_LABEL = 'School-Day Attendance % (this period)'
    # Aeries check-ins are Monthly; a month + grace without one = overdue.
    OVERDUE_AFTER = 45.days

    Row = Struct.new(:client, :programs, :last_contact, :gpa, :attendance_pct,
                     :aeries_date, :overdue, keyword_init: true)

    def initialize(youths:)
      @youths = youths.to_a
    end

    def rows
      @rows ||= @youths.map do |client|
        aeries = aeries_glance[client.id] || {}
        Row.new(client: client,
                programs: programs_by_client.fetch(client.id, []),
                last_contact: last_contact_by_client[client.id],
                gpa: aeries[:gpa],
                attendance_pct: aeries[:attendance],
                aeries_date: aeries[:date],
                overdue: overdue?(client.id, aeries))
      end.sort_by { |row| row.client.name.to_s }
    end

    # One latest Session-agnostic Aeries entry id per PV enrollment — shared
    # with the report-card prefill (HUB2).
    def self.latest_aeries_ids(enrollment_ids)
      return [] if enrollment_ids.empty?
      tracking = aeries_tracking or return []
      ClientEnrollmentTracking
        .from(ClientEnrollmentTracking
                .select('DISTINCT ON (client_enrollment_id) id')
                .where(client_enrollment_id: enrollment_ids, tracking_id: tracking.id)
                .order(:client_enrollment_id, entry_date: :desc, created_at: :desc),
              :client_enrollment_trackings)
        .pluck(:id)
    end

    def self.aeries_tracking
      ProgramStream.find_by(name: AERIES_PROGRAM)
                   &.trackings&.find_by(name: AERIES_TRACKING)
    end

    private

    def client_ids = @youths.map(&:id)

    def programs_by_client
      @programs_by_client ||= ClientEnrollment
                              .where(client_id: client_ids, status: 'Active')
                              .joins(:program_stream)
                              .pluck(:client_id, 'program_streams.name')
                              .group_by(&:first)
                              .transform_values { |pairs| pairs.map(&:last).sort }
    end

    def last_contact_by_client
      @last_contact_by_client ||= ClientEnrollmentTracking
                                  .joins(:client_enrollment)
                                  .where(client_enrollments: { client_id: client_ids })
                                  .group('client_enrollments.client_id')
                                  .maximum(:entry_date)
    end

    def pv_enrollments
      @pv_enrollments ||= begin
        program = ProgramStream.find_by(name: AERIES_PROGRAM)
        program ? ClientEnrollment.where(client_id: client_ids, status: 'Active',
                                         program_stream_id: program.id).to_a : []
      end
    end

    def aeries_glance
      @aeries_glance ||= begin
        ids = self.class.latest_aeries_ids(pv_enrollments.map(&:id))
        client_by_enrollment = pv_enrollments.to_h { |e| [e.id, e.client_id] }
        glance = {}
        Reports::DecryptedScan.each(ClientEnrollmentTracking.where(id: ids)) do |record, props|
          client_id = client_by_enrollment[record.client_enrollment_id] or next
          glance[client_id] = { gpa: props[GPA_LABEL].presence,
                                attendance: props[ATTENDANCE_LABEL].presence,
                                date: record.entry_date }
        end
        glance
      end
    end

    def overdue?(client_id, aeries)
      return false unless pv_enrollments.any? { |e| e.client_id == client_id }
      aeries[:date].nil? || aeries[:date] < OVERDUE_AFTER.ago.to_date
    end
  end
end
