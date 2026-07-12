# Content Security Policy — FedRAMP SC-7 / SI-10, SOC 2 CC6.6 / CC6.8. (POAM-017f)
#
# History: shipped report-only with :https / :unsafe_inline / :unsafe_eval while the front-end
# still carried inline scripts, eval-based template libraries (queryBuilder+doT, formBuilder 1.x)
# and external assets (Google Fonts, a CDN bootstrap link on the error pages, an imgur spinner).
# All of that is gone:
#   - R12A/R12B retired the eval sources (queryBuilder/doT replaced by CIF.RuleBuilder;
#     formBuilder upgraded to the eval-free 3.x),
#   - R12C-1 self-hosted the fonts (public/fonts/open-sans/), de-CDN'd the 404/500 pages,
#     extracted the last two inline onchange handlers, and localized the spinner.
# Every directive now pins to 'self'; scripts are additionally nonce-checked per request.
#
# ENFORCEMENT is env-flag driven (the two_factor.rb ENV.fetch/Boolean-cast pattern — but
# boot-time ENV only, NOT the per-tenant EnforcementSetting panel: CSP is app-global Rack
# middleware config memoized into env_config at boot, so it cannot be tenant-toggled and a
# change always requires a restart/redeploy):
#   ENFORCE_CSP=false -> Content-Security-Policy-Report-Only (shadow mode: browsers
#                        evaluate and REPORT to /csp_reports but block nothing).
#   ENFORCE_CSP unset/true -> Content-Security-Policy (violations BLOCK, and still report).
# ENFORCED BY DEFAULT since 12C-3 (flipped 2026-07-12, user-ratified): the enforce-mode
# Playwright rehearsal recorded ZERO violations across every page + risky surface, and the
# report-only soak's full-coverage pass (TOTP login, XLS export, Dropzone, Trix, builders,
# calendar, error pages) logged zero real csp_violation lines. ENFORCE_CSP=false in .env is
# the operational kill switch (documented in bootstrap.sh) — falls back to shadow mode.
#
# NB: never introduce full-page HTML caching while the nonce generator exists — the nonce is
# minted per request and a cached page would pin a stale one.
Rails.application.configure do
  config.x.enforce_csp =
    ActiveModel::Type::Boolean.new.cast(ENV.fetch('ENFORCE_CSP', true))

  config.content_security_policy do |policy|
    policy.default_src     :self
    policy.base_uri        :self
    policy.object_src      :none
    policy.frame_ancestors :self
    # No frames anywhere app-wide (12C census: zero iframes) — pin shut rather than inherit
    # the default-src fallback. The report-only soak validates this for free; relax to :self
    # with a citation if reports surface a legitimate same-origin frame.
    policy.frame_src       :none
    # form-action has NO default-src fallback — unset means unrestricted. Every form posts
    # same-origin.
    policy.form_action     :self
    # Nonce-based scripts (generator below adds 'nonce-…' per request). 'self' keeps the
    # Sprockets bundle (and debug-mode split files) loading WITHOUT per-tag nonces; the nonce
    # exists for any deliberate future inline <script nonce: true>. A nonce makes browsers
    # ignore 'unsafe-inline' in this directive, so it is dropped outright — as are
    # :unsafe_eval (eval sources retired, R12A/B) and :https (no third-party scripts).
    policy.script_src      :self
    # 'unsafe-inline' is KEPT for style, deliberately (documented POAM-017f residual):
    # FullCalendar 6 and formBuilder 3.x inject runtime <style> elements, the 403/404/500
    # pages use haml :css filters, and legacy inline style= attributes exist throughout.
    # NO nonce on style-src (see nonce_directives below). :https dropped — fonts and the
    # error-page css are self-hosted as of R12C-1.
    policy.style_src       :self, :unsafe_inline
    # :data kept (iCheck/datepicker sprites, formBuilder's base64 icon font pairs with
    # font-src, canvas exports); :https dropped — the imgur spinner was localized in R12C-1.
    policy.img_src         :self, :data
    policy.font_src        :self, :data
    policy.connect_src     :self
    # worker-src / manifest-src / media-src / child-src stay unset ON PURPOSE: no Workers,
    # no web-app manifest, no <audio>/<video> exist, and their fallback chains already land
    # on default-src 'self'. Pinning them would add header bytes without changing policy.
    #
    # Violation reports -> the in-app collector (CspReportsController -> structured
    # Rails.logger line; throttled in rack_attack.rb). report-uri is deprecated-in-spec but
    # universally supported; report-to still needs a separate Reporting-Endpoints header and
    # consistent browser support — revisit if browsers actually drop report-uri.
    policy.report_uri      '/csp_reports'
  end

  # Fresh 128-bit nonce per request. SecureRandom, NOT session.id: the session id is stable
  # for the life of the session (a leaked value would whitelist attacker <script> for days),
  # and sessionless responses would have none. Rails memoizes the generated value per request
  # (request.content_security_policy_nonce), so the header, csp_meta_tag, and any nonce: true
  # helper agree within one response.
  config.content_security_policy_nonce_generator = ->(_request) { SecureRandom.base64(16) }
  # Nonce on script-src ONLY. A nonce on style-src would make browsers IGNORE the
  # 'unsafe-inline' we still rely on for FullCalendar/formBuilder's injected styles.
  config.content_security_policy_nonce_directives = %w[script-src]

  # Enforced by default (12C-3); ENFORCE_CSP=false drops back to report-only shadow mode.
  config.content_security_policy_report_only = !config.x.enforce_csp
end
