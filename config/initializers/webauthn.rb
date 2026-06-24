# WebAuthn passkeys — FedRAMP IA-2. The Relying Party (origin + RP ID) is PER-TENANT-HOST and so
# CANNOT be configured globally here: each tenant is reached on its own subdomain, and the RP ID must
# be the host's registrable domain (lvh.me in dev, cases.<ip>.nip.io / the real host in prod). The
# per-request RelyingParty is built in WebauthnRelyingParty (the controller concern) from request.host.
#
# This initializer only carries the host-independent ceremony parameters (RP display name + the COSE
# algorithms we accept), referenced when constructing the per-request RelyingParty.
module WebauthnConfig
  RP_NAME    = 'CaseLight'.freeze
  ALGORITHMS = %w[ES256 RS256].freeze
end
