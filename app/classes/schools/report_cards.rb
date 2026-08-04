# frozen_string_literal: true

module Schools
  # S3 — report cards as RECORDS: the Aeries check-ins already on file for a
  # school's ¡Por Vida! enrollments, newest first, decrypted for display and
  # each editable through the standard tracking edit page.
  #
  # Decrypt volume is capped: RECENT_LIMIT rows for the index, and exactly one
  # latest row per enrollment for the batch-grid placeholders.
  class ReportCards
    RECENT_LIMIT = 100
    FIELDS = {
      gpa: 'GPA (x100, e.g. 275 = 2.75)',
      credits: 'Credits Earned (cumulative)',
      ag: 'A-G On Track',
      attendance: 'School-Day Attendance % (this period)',
      discipline: 'Discipline Incidents (this period)',
      notes: 'Concerns / IEP-SST Notes'
    }.freeze

    Entry = Struct.new(:record, :client, :enrollment, :report_date, :values, keyword_init: true) do
      def gpa_display
        raw = values[FIELDS[:gpa]]
        raw.present? ? format('%.2f', raw.to_f / 100) : nil
      end
    end

    def initialize(enrollments:)
      @enrollments = enrollments.to_a
    end

    # Report cards on file (newest service date first).
    def recent
      return [] if tracking.nil? || @enrollments.empty?
      by_id = @enrollments.index_by(&:id)
      scope = ClientEnrollmentTracking
              .where(client_enrollment_id: by_id.keys, tracking_id: tracking.id)
              .order(entry_date: :desc, created_at: :desc)
              .limit(RECENT_LIMIT)
      Reports::DecryptedScan.rows(scope).map do |row|
        enrollment = by_id[row[:record].client_enrollment_id]
        Entry.new(record: row[:record], client: enrollment&.client, enrollment: enrollment,
                  report_date: row[:record].entry_date, values: row[:props] || {})
      end.sort_by { |entry| [-entry.report_date.to_time.to_i, entry.client&.name.to_s] }
    end

    # { client_id => properties } from each enrollment's LATEST entry — the batch
    # grid's placeholders (never values).
    def latest_props_by_client
      ids = Schools::Roster.latest_aeries_ids(@enrollments.map(&:id))
      client_by_enrollment = @enrollments.to_h { |e| [e.id, e.client_id] }
      prefills = {}
      Reports::DecryptedScan.each(ClientEnrollmentTracking.where(id: ids)) do |record, props|
        client_id = client_by_enrollment[record.client_enrollment_id] or next
        prefills[client_id] = props
      end
      prefills
    end

    private

    def tracking
      @tracking ||= Schools::Roster.aeries_tracking
    end
  end
end
