# Builds the per-request WebAuthn::RelyingParty. Shared by PasskeysController (registration) and
# SessionsController (passwordless authentication).
#
# The RP ID MUST be a registrable suffix of the origin host or the browser silently refuses to
# create/use the credential. In the subdomain-tenant model the registrable domain (eTLD+1) is what we
# want so a passkey works across the tenant subdomain (e.g. cases.lvh.me -> RP ID "lvh.me";
# cases.<ip>.nip.io -> "nip.io"-suffixed registrable domain). We approximate eTLD+1 as the last two
# DNS labels of request.host, which is correct for lvh.me / nip.io / a normal two-label prod domain.
#
# CAVEAT (documented for the operator): on a bare EC2 IP host (no domain) there is no registrable
# domain, so passkeys cannot work there — this intersects the CLAUDE.md open question about needing a
# real hostname before multi-tenant routing works. WebAuthn also requires a SECURE CONTEXT
# (HTTPS, or http://localhost|127.0.0.1) in the browser; plain http on cases.lvh.me will throw.
module WebauthnRelyingParty
  extend ActiveSupport::Concern

  private

  def relying_party
    WebAuthn::RelyingParty.new(
      origin:     request.base_url,
      name:       WebauthnConfig::RP_NAME,
      id:         relying_party_id,
      algorithms: WebauthnConfig::ALGORITHMS
    )
  end

  # eTLD+1 approximation: the last two labels of the request host. For a single-label/empty host
  # (e.g. a bare IP, "localhost"), fall back to the host itself.
  def relying_party_id
    labels = request.host.to_s.split('.')
    labels.length >= 2 ? labels.last(2).join('.') : request.host.to_s
  end
end
