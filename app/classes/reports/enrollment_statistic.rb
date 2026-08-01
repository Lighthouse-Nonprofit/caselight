# frozen_string_literal: true

module Reports
  # The Reports landing-page chart data: ACTIVE enrollments per program over the
  # trailing 12 months. Replaces CaseStatistic (which hardwired the EC/FC/KC
  # care-placement case types — legacy-wrong in both flavors); program names
  # come from the tenant's own seeded ProgramStreams, so the chart is
  # flavor-correct everywhere. Same [labels, series] lineChart contract.
  class EnrollmentStatistic
    def initialize(clients)
      @client_ids = clients.ids
    end

    def statistic_data
      months = trailing_months
      labels = months.map { |m| m.strftime('%b-%y') }
      series = ProgramStream.order(:name).map do |program|
        enrollments = ClientEnrollment.where(client_id: @client_ids,
                                             program_stream_id: program.id)
                                      .left_joins(:leave_program)
        data = months.map do |month|
          month_end = month.end_of_month
          enrollments.where(enrollment_date: ..month_end)
                     .where('leave_programs.id IS NULL OR leave_programs.exit_date > ?', month_end)
                     .count
        end
        { name: program.name, data: data }
      end
      [labels, series]
    end

    private

    def trailing_months
      current = Time.zone.today.beginning_of_month
      (0..11).map { |i| current << (11 - i) }
    end
  end
end
