# frozen_string_literal: true

module Reports
  module Manager
    # M2 — the worker-tier compliance engine aggregated for operations: overdue
    # check-in counts per program × worker, and how many households/individuals
    # have gone 30/60+ days without a service contact.
    class FollowUpCompliance < BaseReport
      GRACE_DAYS = Reports::Worker::FollowUpCompliance::GRACE_DAYS

      private

      def build_sections
        [overdue_matrix_section, no_contact_summary_section]
      end

      def overdue_matrix_section
        today = Time.zone.today
        counts = Hash.new(0)
        enrollments = scoped_enrollments.where(status: 'Active')
                                        .includes(:client, program_stream: :trackings)
        last_by_pair = ClientEnrollmentTracking
                       .where(client_enrollment_id: enrollments.map(&:id))
                       .group(:client_enrollment_id, :tracking_id)
                       .maximum(:entry_date)
        workers_by_client = CaseWorkerClient.where(client_id: client_ids)
                                            .pluck(:client_id, :user_id)
                                            .group_by(&:first)
                                            .transform_values { |pairs| pairs.map(&:last) }
        worker_names = User.where(id: workers_by_client.values.flatten.uniq)
                           .index_by(&:id).transform_values(&:name)

        enrollments.each do |enrollment|
          enrollment.program_stream.trackings.each do |tracking|
            grace = GRACE_DAYS[tracking.frequency] or next
            last = last_by_pair[[enrollment.id, tracking.id]] ||
                   enrollment.enrollment_date || enrollment.created_at.to_date
            next unless last + grace < today
            workers = workers_by_client.fetch(enrollment.client_id, [nil])
            workers.each do |worker_id|
              label = worker_names.fetch(worker_id, I18n.t('reports.registry.follow_up_compliance.unassigned'))
              counts[[enrollment.program_stream.name, label]] += 1
            end
          end
        end

        rows = counts.sort.map { |(program, worker), count| [program, worker, count] }
        Section.new(key: :overdue_matrix,
                    columns: cols(%w[program worker overdue]),
                    rows: rows)
      end

      def no_contact_summary_section
        today = Time.zone.today
        last = ClientEnrollmentTracking
               .joins(:client_enrollment)
               .where(client_enrollments: { client_id: client_ids })
               .group('client_enrollments.client_id')
               .maximum(:entry_date)
        stale30 = []
        stale60 = []
        client_ids.each do |id|
          date = last[id]
          gap = date ? (today - date).to_i : nil
          stale30 << id if gap.nil? || gap >= 30
          stale60 << id if gap.nil? || gap >= 60
        end
        rows = [
          [I18n.t('reports.registry.follow_up_compliance.no_contact_30'), stale30.size, household_count(stale30)],
          [I18n.t('reports.registry.follow_up_compliance.no_contact_60'), stale60.size, household_count(stale60)]
        ]
        Section.new(key: :no_contact, columns: cols(%w[bucket individuals households]), rows: rows)
      end

      def cols(keys)
        keys.map { |k| I18n.t("reports.registry.follow_up_compliance.columns.#{k}") }
      end
    end
  end
end
