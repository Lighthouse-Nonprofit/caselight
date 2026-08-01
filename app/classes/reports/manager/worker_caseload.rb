# frozen_string_literal: true

module Reports
  module Manager
    # M1 — caseload distribution across the workers the viewer supervises (the
    # worker set is derived from the clients the viewer's ability admits, so a
    # manager sees their team and an admin the org). Zero-caseload workers on
    # the team still render — an idle worker is a finding, not a blank.
    class WorkerCaseload < BaseReport
      private

      def build_sections
        links = CaseWorkerClient.where(client_id: client_ids)
        worker_ids = links.distinct.pluck(:user_id)
        workers = User.where(id: worker_ids)

        contacts = ClientEnrollmentTracking
                   .joins(client_enrollment: { client: :case_worker_clients })
                   .where(entry_date: period.range,
                          client_enrollments: { client_id: client_ids })
                   .group('case_worker_clients.user_id').count

        assessments = Assessment
                      .joins(client: :case_worker_clients)
                      .where(created_at: period.range.begin.beginning_of_day..period.range.end.end_of_day,
                             client_id: client_ids)
                      .group('case_worker_clients.user_id').count

        enrollment_counts = ClientEnrollment
                            .joins(client: :case_worker_clients)
                            .where(status: 'Active', client_id: client_ids)
                            .group('case_worker_clients.user_id').count

        caseloads = links.group(:user_id).count

        rows = workers.sort_by { |w| w.name.to_s }.map do |worker|
          [worker.name,
           caseloads.fetch(worker.id, 0),
           enrollment_counts.fetch(worker.id, 0),
           contacts.fetch(worker.id, 0),
           assessments.fetch(worker.id, 0),
           worker.disable? ? I18n.t('reports.registry.worker_caseloads.disabled_flag') : '']
        end

        [Section.new(key: :caseloads, columns: cols, rows: rows,
                     footnote: I18n.t('reports.registry.worker_caseloads.footnote'))]
      end

      def cols
        %w[worker clients active_enrollments contacts assessments flags].map do |key|
          I18n.t("reports.registry.worker_caseloads.columns.#{key}")
        end
      end
    end
  end
end
