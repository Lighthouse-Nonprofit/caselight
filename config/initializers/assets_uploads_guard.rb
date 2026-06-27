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

# Insert BEFORE the static file server so the deny wins over public/ file serving in every env where
# static files are served (test: serve_static_files=true; prod: RAILS_SERVE_STATIC_FILES). Guard the
# insert so boot never fails if the middleware stack shape changes.
Rails.application.config.app_middleware.insert_before(ActionDispatch::Static, UploadsStaticGuard) rescue Rails.application.config.app_middleware.use(UploadsStaticGuard)
