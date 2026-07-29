# frozen_string_literal: true

# POAM-019 (PR B2) — the WARM PDF-generation surface. The archived wkhtmltopdf/Qt-WebKit engine
# left with the government-reports feature (PR B1); this is its maintained replacement: headless
# Chromium driven over CDP by Ferrum (the same engine cuprite runs the feature suite on — no Node,
# no new toolchain, the chromium binary is baked into the image).
#
# DELIBERATELY NO USER-FACING FEATURE YET: per-flavor reporting builds on this later. What "warm"
# means: both entry points below work end-to-end in the image and are pinned by
# spec/lib/pdf_renderer_spec.rb (%PDF- magic bytes, non-trivial size, template path through the
# `pdf` layout). When reporting lands, it calls render_template with a real template and a
# controller-provided assigns hash — nothing here changes.
#
# Rendering contract:
#   * SELF-CONTAINED HTML ONLY. The layout (app/views/layouts/pdf.html.haml) inlines its styles
#     and references no app assets — the render must stay network-free (the CSP posture's
#     external_asset_reference_guard scans every haml view, this layout included).
#   * The page is loaded from a tempfile over file:// (no app server involved, no cookies, no
#     session — the renderer NEVER sees authenticated state; callers pass fully-resolved data).
#   * Chromium runs headless with the same container flags the cuprite suite uses
#     (no-sandbox / disable-gpu / disable-dev-shm-usage) and is always quit, even on error.
class PdfRenderer
  DEFAULT_PDF_OPTIONS = { format: :A4, print_background: true }.freeze

  class ChromiumMissing < StandardError; end

  class << self
    # Lowest-level entry point: HTML string in, PDF bytes out.
    def render_html(html, **pdf_options)
      raise ChromiumMissing, 'no chromium/chrome binary found (bake it into the image — see Dockerfile)' unless available?

      Tempfile.create(['pdf_render', '.html']) do |file|
        file.binmode
        file.write(html)
        file.flush

        browser = Ferrum::Browser.new(
          headless: true,
          timeout: 60,
          process_timeout: 30,
          browser_path: browser_path,
          browser_options: { 'no-sandbox' => nil, 'disable-gpu' => nil, 'disable-dev-shm-usage' => nil }
        )
        begin
          page = browser.create_page
          page.go_to("file://#{file.path}")
          page.pdf(**DEFAULT_PDF_OPTIONS.merge(pdf_options).merge(encoding: :binary))
        ensure
          browser&.quit
        end
      end
    end

    # Template entry point — what reporting will call. Renders OUTSIDE any request (no session,
    # no current_user; pass everything via assigns) through the self-contained `pdf` layout.
    def render_template(template:, assigns: {}, layout: 'pdf', **pdf_options)
      html = ApplicationController.render(template: template, layout: layout, assigns: assigns)
      render_html(html, **pdf_options)
    end

    # True when a Chromium/Chrome binary is resolvable — the smoke spec skips (rather than
    # fails) on runners without one (the CI subset has no browser; the image and dev do).
    def available?
      browser_path.present?
    end

    def browser_path
      return ENV['BROWSER_PATH'] if ENV['BROWSER_PATH'].present? && File.executable?(ENV['BROWSER_PATH'])

      %w[/usr/bin/chromium /usr/bin/chromium-browser /usr/bin/google-chrome /usr/bin/google-chrome-stable].find do |candidate|
        File.executable?(candidate)
      end
    end
  end
end
