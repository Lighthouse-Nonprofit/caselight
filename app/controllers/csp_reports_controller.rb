# frozen_string_literal: true

# CSP violation report sink (POAM-017f) — FedRAMP SI-4 / SC-7 visibility for the CSP control.
# Browsers POST application/csp-report here (the policy's report-uri directive), credential-less
# and token-less by design, so this endpoint accepts unauthenticated, CSRF-exempt POSTs.
# Defenses instead: the rack_attack throttle (csp_reports/ip), an 8 KB body cap, tolerant
# parsing that never 500s, and a PII-scrubbed single-line log (paths only — never query
# strings, never user data). Always 204, even for junk — the endpoint must not be a parser
# oracle. Log lines are grep-able as `csp_violation` (the soak's zero-violation gate).
class CspReportsController < ApplicationController
  MAX_BODY_BYTES = 8.kilobytes

  # Public sink — no resource to authorize (Phase-5.6 allowlist discipline; ErrorsController
  # precedent). CSRF skipped because browser CSP reporters send no token.
  skip_authorization_check
  skip_forgery_protection

  def create
    length = request.content_length.to_i
    return head :no_content unless length.positive? && length <= MAX_BODY_BYTES

    payload = begin
      JSON.parse(request.body.read(MAX_BODY_BYTES).to_s)
    rescue JSON::ParserError, EncodingError
      nil
    end
    report = payload.is_a?(Hash) ? payload['csp-report'] : nil

    if report.is_a?(Hash)
      Rails.logger.warn({
        event: 'csp_violation',
        directive: report['effective-directive'] || report['violated-directive'],
        blocked: scrub(report['blocked-uri']),
        document: scrub(report['document-uri']),
        source_file: scrub(report['source-file']),
        line: report['line-number'],
        disposition: report['disposition']
      }.compact.to_json)
    end
    head :no_content
  end

  private

  # Keep scheme+host+path, drop query/fragment (PII rides in query params), truncate.
  def scrub(uri)
    return nil if uri.blank?

    uri.to_s.split(/[?#]/, 2).first.to_s.first(200)
  end
end
