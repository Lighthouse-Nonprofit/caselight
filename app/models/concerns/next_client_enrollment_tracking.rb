module NextClientEnrollmentTracking
  # Y2(b): the due date for ONE tracking within ONE enrollment. Two long-standing bugs
  # died in this rewrite:
  #   * callers passed `client_enrollment_trackings.last` UNSCOPED — with two trackings
  #     on a program, logging one reset the other's clock;
  #   * a frequency-bearing tracking with ZERO entries crashed the notification path
  #     (nil.created_at). The clock now starts at the enrollment date.
  # Dates reason on entry_date (Y2a), not created_at.
  def next_client_enrollment_tracking_date(tracking, enrollment)
    last = enrollment.client_enrollment_trackings
                     .enrollment_trackings_by(tracking)
                     .order(:entry_date, :created_at).last
    base = last&.entry_date || enrollment.enrollment_date
    base + tracking_frequency(tracking)
  end

  private

  def tracking_frequency(tracking)
    frequency = tracking.frequency
    # HUB2 hardening: a frequency-bearing tracking with NO time_of_frequency
    # (hand-created or minimally seeded) crashed every page for assigned
    # workers via the notification bell (nil.week). Default to every 1 period.
    time_of_frequency = tracking.time_of_frequency.presence || 1
    case frequency
    when 'Daily'   then time_of_frequency.day
    when 'Weekly'  then time_of_frequency.week
    when 'Monthly' then time_of_frequency.month
    when 'Yearly'  then time_of_frequency.year
    else 0.day
    end
  end
end
