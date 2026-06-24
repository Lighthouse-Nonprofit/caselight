# Be sure to restart your server when you modify this file.

# Session-cookie hardening — FedRAMP SC-23 (session authenticity) / AC-12, SOC 2 CC6.7.
# Made explicit (rather than relying on framework defaults) so the control is auditable.
# Preserves the existing cookie key so deploying this does NOT invalidate active sessions.
#
#  - httponly:  JavaScript cannot read the session cookie (mitigates XSS session theft).
#  - same_site: :lax — the cookie is not sent on cross-site POSTs (CSRF defense-in-depth).
#  - secure:    HTTPS-only in production. (force_ssl also flags cookies secure; set explicitly
#               here for the audit trail.) Left off in dev/test so cookies work over plain HTTP.
Rails.application.config.session_store :cookie_store,
  key:       '_cif-web_session',
  httponly:  true,
  same_site: :lax,
  secure:    Rails.env.production?

