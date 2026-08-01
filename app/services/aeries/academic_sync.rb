# frozen_string_literal: true

module Aeries
  # SCH3 — maps Aeries academic records onto Academic Check-in (Aeries) tracking
  # entries. SCAFFOLD: the transformation + matching + idempotency are real and
  # spec-pinned; the HTTP layer (Aeries::Client) stays disabled until the SMJUHSD
  # data-sharing authorization lands.
  #
  #   * Matching: Aeries StudentID -> the 'Student ID (Aeries)' field on the
  #     Referral & Intake form, probed via the Tier-5 SIDECAR (deterministic
  #     equality — never a decrypt scan).
  #   * Idempotency: at most one entry per (enrollment, report date) — re-syncs
  #     never duplicate.
  #   * DRY-RUN by default; writes only with confirm: true (casebook precedent).
  #   * records shape (one per student):
  #       { 'StudentID' => '12345', 'ReportDate' => '2026-11-01', 'GPA' => 2.85,
  #         'CreditsEarned' => 120, 'AttendancePercent' => 93.0,
  #         'DisciplineIncidents' => 0, 'AGOnTrack' => true }
  class AcademicSync
    PROGRAM_NAME = '¡Por Vida!'
    TRACKING_NAME = 'Academic Check-in (Aeries)'
    STUDENT_ID_FORM = 'Referral & Intake'
    STUDENT_ID_FIELD = 'Student ID (Aeries)'

    Result = Struct.new(:matched, :unmatched, :created, :skipped_existing, :dry_run, keyword_init: true)

    def initialize(records, confirm: false)
      @records = Array(records)
      @confirm = confirm
    end

    def run!
      result = Result.new(matched: 0, unmatched: 0, created: 0, skipped_existing: 0, dry_run: !@confirm)
      program = ProgramStream.find_by(name: PROGRAM_NAME) or return result
      tracking = program.trackings.find_by(name: TRACKING_NAME) or return result
      form = CustomField.find_by(entity_type: 'Client', form_title: STUDENT_ID_FORM)

      @records.each do |record|
        client_id = match_client_id(form, record['StudentID'])
        next result.unmatched += 1 if client_id.nil?
        result.matched += 1

        enrollment = ClientEnrollment.find_by(client_id: client_id,
                                              program_stream_id: program.id, status: 'Active')
        next result.unmatched += 1 if enrollment.nil?

        date = Date.parse(record['ReportDate'].to_s)
        if ClientEnrollmentTracking.exists?(client_enrollment_id: enrollment.id,
                                            tracking_id: tracking.id, entry_date: date)
          result.skipped_existing += 1
          next
        end
        next if result.dry_run

        ClientEnrollmentTracking.create!(
          client_enrollment_id: enrollment.id, tracking_id: tracking.id, entry_date: date,
          properties: properties_from(record)
        )
        result.created += 1
      rescue Date::Error
        result.unmatched += 1
      end
      result
    end

    private

    # Sidecar deterministic equality — no ciphertext scans, no name matching.
    def match_client_id(form, student_id)
      return nil if form.nil? || student_id.blank?
      CustomFieldPropertySearchEntry
        .joins("INNER JOIN custom_field_properties cfp ON cfp.id = custom_field_property_search_entries.custom_field_property_id")
        .where(field_label: STUDENT_ID_FIELD, value: student_id.to_s)
        .where(cfp: { custom_field_id: form.id, custom_formable_type: 'Client' })
        .pick('cfp.custom_formable_id')
    end

    def properties_from(record)
      {
        'GPA (x100, e.g. 275 = 2.75)' => record['GPA'].nil? ? nil : (record['GPA'].to_f * 100).round.to_s,
        'Credits Earned (cumulative)' => record['CreditsEarned']&.to_s,
        'School-Day Attendance % (this period)' => record['AttendancePercent']&.to_s,
        'Discipline Incidents (this period)' => record['DisciplineIncidents']&.to_s,
        'A-G On Track' => record['AGOnTrack'].nil? ? nil : (record['AGOnTrack'] ? 'On track' : 'At risk')
      }.compact
    end
  end
end
