# Data-task batch D6 — the client-direct email feature flip. Owner decision: "build out
# the direct email client, but have it be a feature flip on SMTP config, and default to
# case team, staff side." With no real SMTP config, behavior is EXACTLY today's
# staff-only mail flow; when ops provides SES creds + a real SENDER_EMAIL, consented
# clients with an email start getting reminders too — no deploy, no code change.
class ClientMessaging
  # The pilot box ships SENDER_EMAIL=nil (the LITERAL string) — same trap
  # GoogleCalendarPush.enabled? guards against; treat 'nil'/blank as unset.
  def self.enabled?
    sender_email.present? && smtp_configured?
  end

  def self.sender_email
    value = ENV['SENDER_EMAIL']
    return nil unless configured?(value)
    value
  end

  def self.smtp_configured?
    configured?(ENV['AWS_SES_USER_NAME']) && configured?(ENV['AWS_SES_PASSWORD'])
  end

  def self.configured?(value)
    value.present? && value.strip.downcase != 'nil'
  end
end
