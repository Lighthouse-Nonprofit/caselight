class ApplicationMailer < ActionMailer::Base
  # D6: SENDER_EMAIL arrives as the literal string "nil" on unconfigured boxes — treat it
  # as unset (ClientMessaging.sender_email) so the from header stays well-formed either
  # way. Staff mail still fails visibly at SMTP until ops provides real creds; the
  # client-direct sends are additionally gated by ClientMessaging.enabled?. Lambda so the
  # env is read per-mail, not at class load.
  default from: -> { ClientMessaging.sender_email || 'caselight@localhost' }
  layout 'mailer'
end
