# Data-task batch D6 — the client-direct reminder (feature-flipped: only ever invoked
# when ClientMessaging.enabled? AND the client consented AND an email is on file).
# VALUES-LEAN by design: task names can carry case context, so the body says only that
# appointments/tasks are scheduled tomorrow, with times for timed ones — no domains, no
# notes, no case narrative (values-free audit-logging discipline applied to email).
class ClientReminderMailer < ApplicationMailer
  def task_reminder(client, tasks)
    @client_name = client.given_name.presence || 'there'
    @org_name    = Organization.current&.full_name.presence || 'your resettlement team'
    # wall-clock times only for timed tasks; all-day ones just count
    @timed_times = tasks.select(&:timed?).map { |t| t.starts_at.strftime('%l:%M %p').strip }
    @task_count  = tasks.size
    mail(to: client.email, subject: 'Reminder: you have an appointment tomorrow')
  end
end
