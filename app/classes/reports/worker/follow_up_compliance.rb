# frozen_string_literal: true

module Reports
  module Worker
    # W2 — the daily-discipline report: which check-ins are overdue (per active
    # enrollment × frequency-bearing tracking), who has had no contact in
    # 30/60 days, and the viewer's overdue/today tasks. Grace windows convert
    # the tracking cadence into an overdue threshold.
    class FollowUpCompliance < BaseReport
      GRACE_DAYS = { 'Daily' => 2, 'Weekly' => 10, 'Monthly' => 35, 'Yearly' => 370 }.freeze

      private

      def build_sections
        [overdue_checkins_section, no_contact_section, tasks_section]
      end

      def overdue_checkins_section
        today = Time.zone.today
        rows = []
        enrollments = scoped_enrollments.where(status: 'Active')
                                        .includes(:client, program_stream: :trackings)
        last_by_pair = ClientEnrollmentTracking
                       .where(client_enrollment_id: enrollments.map(&:id))
                       .group(:client_enrollment_id, :tracking_id)
                       .maximum(:entry_date)

        enrollments.each do |enrollment|
          enrollment.program_stream.trackings.each do |tracking|
            grace = GRACE_DAYS[tracking.frequency] or next
            last = last_by_pair[[enrollment.id, tracking.id]] ||
                   enrollment.enrollment_date || enrollment.created_at.to_date
            due = last + grace
            next unless due < today
            rows << [client_label(enrollment.client), enrollment.program_stream.name,
                     tracking.name, last, (today - due).to_i]
          end
        end
        rows.sort_by! { |r| -r.last }

        Section.new(key: :overdue_checkins, columns: cols(%w[client program tracking last_entry days_overdue]),
                    rows: rows)
      end

      def no_contact_section
        today = Time.zone.today
        last = ClientEnrollmentTracking
               .joins(:client_enrollment)
               .where(client_enrollments: { client_id: client_ids })
               .group('client_enrollments.client_id')
               .maximum(:entry_date)
        rows = @clients.map do |client|
          date = last[client.id]
          gap = date ? (today - date).to_i : nil
          next if gap && gap < 30
          [client_label(client), date || I18n.t('reports.show.no_data'),
           gap || I18n.t('reports.show.unknown')]
        end.compact
        Section.new(key: :no_contact, columns: cols(%w[client last_contact days_since]), rows: rows)
      end

      def tasks_section
        overdue = Task.overdue_incomplete.where(client_id: client_ids).includes(:client)
        today_tasks = Task.today_incomplete.where(client_id: client_ids).includes(:client)
        rows = overdue.map { |t| [client_label(t.client), t.name, t.completion_date, I18n.t('reports.registry.my_follow_up_compliance.overdue')] } +
               today_tasks.map { |t| [client_label(t.client), t.name, t.completion_date, I18n.t('reports.registry.my_follow_up_compliance.due_today')] }
        Section.new(key: :tasks, columns: cols(%w[client task due status]), rows: rows)
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.my_follow_up_compliance.columns.#{k}") }
      end
    end
  end
end
