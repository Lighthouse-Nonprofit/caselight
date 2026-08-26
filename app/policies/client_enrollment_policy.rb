class ClientEnrollmentPolicy < ApplicationPolicy
  # OCA 2026-08-26 -- both gates below used to key on (client, program) alone, i.e. a program's
  # entire lifetime history:
  #
  #   * `cohort_history` refused a youth who was Active in ANY earlier cohort of the same program,
  #     so nobody could be enrolled into a new term.
  #   * `client_ids` counted every client ever active in the program against a single `quantity`.
  #     youth:seed_programs stamped quantity: 30 on every program, so the 31st youth ever active was
  #     refused -- on OCA that had already hard-blocked El Joven Noble (164), Girasol (51),
  #     Nurturing Our Futures (41) and Celebracion (38).
  #
  # Both are now scoped to the cohort being enrolled into. Failure here raises
  # Pundit::NotAuthorizedError, which ApplicationController turns into a generic "unauthorized"
  # redirect to root -- which is why this looked mysterious rather than like a capacity limit.
  def create?
    return false unless cohort_history.empty? || cohort_history.last.status == 'Exited'
    return true if capacity.blank?

    client_ids.size < capacity
  end

  # Clients occupying a place in THIS cohort. `for_active_clients` excludes blank-status historic
  # imports, matching what ProgramStreamDecorator already shows as "places left" -- before this the
  # displayed count and the enforced cap disagreed.
  def client_ids
    ClientEnrollment.active
                    .for_active_clients
                    .where(program_stream_id: record.program_stream_id)
                    .in_cohort(cohort_key)
                    .distinct
                    .pluck(:client_id)
  end

  private

  def capacity
    record.program_stream&.quantity
  end

  # Derived, not the persisted column: the record being authorized has not been saved yet.
  def cohort_key
    record.derived_cohort_key
  end

  def cohort_history
    ClientEnrollment.where(client_id: record.client_id,
                           program_stream_id: record.program_stream_id)
                    .in_cohort(cohort_key)
                    .order(:created_at)
  end
end
