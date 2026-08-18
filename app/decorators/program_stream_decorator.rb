class ProgramStreamDecorator < Draper::Decorator
  delegate_all

  def enrollment_status_value(client)
    enrollments = model.client_enrollments.enrollments_by(client).order(:created_at)
    return unless enrollments.present?
    enrollments.last.status
  end

  # Badge VARIANTS, not class strings — rendering goes through the cl_badge chokepoint
  # (BS5 prep, POAM-017g P1) so the framework class names live in exactly one helper.
  def enrollment_status_variant(client)
    return if enrollment_status_value(client).nil?

    enrollment_status_value(client) == 'Active' ? :primary : :danger
  end

  def completed_variant
    model.completed? ? :primary : :danger
  end

  def completed_status
    model.completed? ? 'Completed' : 'Incompleted'
  end

  # Owner-set lifecycle (Pending / Active / Completed) — the user-facing program state, shown on
  # the programs list. (completed_status above is the internal config-readiness flag, kept for the
  # program's own config page.)
  def lifecycle_status
    model.status.to_s.titleize.presence || 'Active'
  end

  def lifecycle_variant
    { 'active' => :success, 'pending' => :warning, 'completed' => :secondary }
      .fetch(model.status.to_s, :secondary)
  end

  # Currently-enrolled (active) clients — always the real count now (was gated on the config
  # flag, which showed blank for not-yet-fully-built programs).
  def active_enrollment_count
    model.client_enrollments.active.size
  end

  def maximum_client?
    model.quantity.present? && model.client_enrollments.active.size >= model.quantity
  end

  def place_available
    model.quantity.present? ? model.number_available_for_client : ''
  end

  def enrolled
    model.completed == true ? model.client_enrollments.active.size : ''
  end

  def domains_format
    model.domains.pluck(:identity)
  end
end
