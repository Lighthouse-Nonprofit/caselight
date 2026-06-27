# frozen_string_literal: true

# Phase 5.3 (NIST AC-6 / SC-28) — assessment_domain attachments are stored on the CarrierWave :file
# backend under public/uploads/assessment_domain/attachments/<id>/<file> and would otherwise be served
# directly by Rails' static file middleware (config.serve_static_files) at a GUESSABLE URL, bypassing
# the sensitivity-gated download action. Deny ALL direct static requests under that path; the ONLY
# supported serve path is GET .../assessments/:id/assessment_domains/:adid/attachments/:index
# (AssessmentsController#download_attachment), which authorizes :read on the client AND checks the
# domain's sensitivity before send_file. Returns a static 403 (never a redirect, never the bytes).
class UploadsStaticGuard
  DENY = %r{\A/uploads/assessment_domain/}i.freeze

  def initialize(app)
    @app = app
  end

  def call(env)
    path = env['PATH_INFO'].to_s
    if path.match?(DENY)
      return [403, { 'Content-Type' => 'text/plain', 'X-Content-Type-Options' => 'nosniff' }, ['Not authorized']]
    end
    @app.call(env)
  end
end

# Insert at the FRONT of the stack so the deny wins over public/ static file serving (when
# ActionDispatch::Static is present, e.g. prod) AND boots cleanly when it is ABSENT (e.g. the test
# env, where public_file_server is off). The original insert_before(ActionDispatch::Static, ...)
# raised at stack-build time when Static was missing — and the `rescue … use(…)` fallback (which
# runs at config time, not build time) could not catch it, leaving the stack malformed (a Symbol
# where the next app should be -> a 500 on every request). A fixed index 0 is always valid.
Rails.application.config.app_middleware.insert_before(0, UploadsStaticGuard)
