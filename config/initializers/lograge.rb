# Structured (JSON) request logging — FedRAMP AU-3 (content of audit records), SOC 2 CC7.2.
# Each request collapses to a single JSON line carrying the who/what/where/when an auditor needs:
# the request id, the acting user, the tenant, the source IP, and a UTC timestamp (on top of lograge's
# default method/path/controller/action/status/duration). This is the structured stream that ships to
# the WORM/CloudWatch log sink (the retention + shipping piece is the infra hand-off; see AU-9/AU-11).
#
# Disabled in test to keep the suite output readable — the tag-building logic
# (ApplicationController#append_info_to_payload) is unit-tested directly instead.
Rails.application.configure do
  config.lograge.enabled   = !Rails.env.test?
  config.lograge.formatter = Lograge::Formatters::Json.new

  config.lograge.custom_options = lambda do |event|
    {
      time:       Time.now.utc.iso8601,
      request_id: event.payload[:request_id],
      user_id:    event.payload[:user_id],
      tenant:     event.payload[:tenant],
      remote_ip:  event.payload[:remote_ip]
    }.compact
  end
end
