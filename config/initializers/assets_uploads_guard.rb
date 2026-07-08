# frozen_string_literal: true

# Phase 5.3 -> Phase 6 (NIST AC-6 / SC-28, POAM-SC28-UPLOADS). CarrierWave stores under
# public/uploads/<model>/<mount>/<id>/<file>, which Rails' static file middleware would serve at a
# GUESSABLE URL with no authorization. Phase 5.3 denied only assessment_domain; Phase 6 closes the
# rest: deny ALL of /uploads/** EXCEPT the organization logo (login-page branding, non-PII, must
# stay public). The only supported serve paths are the authorized controllers —
# AssessmentsController#download_attachment (assessment_domain) and DownloadsController#show
# (everything else) — which authorize the readable parent record and apply the Phase-5.3
# sensitivity gates before send_file. Returns a static 403 (never a redirect, never the bytes).
#
# ENV kill-switch (rollback without a deploy): UPLOADS_GUARD_ALLOW_ALL=1 restores the Phase-5.3
# assessment_domain-only deny. Documented in the Phase-6 PR; remove once the new routes have soaked.
class UploadsStaticGuard
  DENY_ALL    = %r{\A/uploads/}i.freeze
  ALLOW       = %r{\A/uploads/organization/}i.freeze
  DENY_LEGACY = %r{\A/uploads/assessment_domain/}i.freeze

  def initialize(app)
    @app = app
    @legacy_mode = ENV['UPLOADS_GUARD_ALLOW_ALL'] == '1'
  end

  def call(env)
    path = env['PATH_INFO'].to_s
    if denied?(path)
      return [403, { 'Content-Type' => 'text/plain', 'X-Content-Type-Options' => 'nosniff' }, ['Not authorized']]
    end
    @app.call(env)
  end

  private

  def denied?(path)
    return path.match?(DENY_LEGACY) if @legacy_mode

    path.match?(DENY_ALL) && !path.match?(ALLOW)
  end
end

# Insert at the FRONT of the stack so the deny wins over public/ static file serving (when
# ActionDispatch::Static is present, e.g. prod) AND boots cleanly when it is ABSENT (e.g. the test
# env, where public_file_server is off). The original insert_before(ActionDispatch::Static, ...)
# raised at stack-build time when Static was missing — and the `rescue … use(…)` fallback (which
# runs at config time, not build time) could not catch it, leaving the stack malformed (a Symbol
# where the next app should be -> a 500 on every request). A fixed index 0 is always valid.
Rails.application.config.app_middleware.insert_before(0, UploadsStaticGuard)
