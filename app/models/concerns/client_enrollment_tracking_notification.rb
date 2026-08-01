module ClientEnrollmentTrackingNotification
  # Y2(b): iterate the PROGRAM's trackings (not the has_many-through, which only sees
  # trackings that already have entries), and let next_client_enrollment_tracking_date
  # scope the clock per tracking with an enrollment-date fallback.
  def client_enrollment_tracking_notification(clients)
    clients_due_today = []
    clients_overdue = []
    clients.each do |client|
      client_active_enrollments = client.client_enrollments.active
      client_active_enrollments.each do |client_active_enrollment|
        trackings = client_active_enrollment.program_stream.trackings
        trackings.each do |tracking|
          next unless tracking.frequency.present?
          due = client.next_client_enrollment_tracking_date(tracking, client_active_enrollment)
          if due < Time.zone.today
            clients_overdue << client
          elsif due == Time.zone.today
            clients_due_today << client
          end
        end
      end
    end
    { clients_overdue: clients_overdue.uniq, clients_due_today: clients_due_today.uniq }
  end
end
