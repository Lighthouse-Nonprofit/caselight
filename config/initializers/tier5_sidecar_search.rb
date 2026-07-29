# frozen_string_literal: true

# POAM-024 (PR A3) — read-path mode for the Tier-5 search-entry sidecar
# (PropertiesSearchEntry + AdvancedSearches::PropertiesFilter#apply). Three states,
# ENFORCE_CSP-style, resolved ONCE at boot from ENV:
#
#   off    -> legacy in-Ruby decrypt-and-filter only (the kill switch)
#   shadow -> serve LEGACY results, also run the sidecar path and write a values-free
#             `tier5_sidecar_shadow` AccessLog system event on any result-set divergence
#             (the DEFAULT; AuthorizationShadow / CSP report-only precedent — flip only
#             after a zero-divergence soak)
#   on     -> sidecar-served: equality family (equal/not_equal/is_empty/is_not_empty —
#             the only operators dropdown/radio/checkbox fields offer) = indexed SQL
#             against the entry tables; contains/ordered/between = presence-prefiltered
#             Ruby over the oracle-verified match? (a guaranteed superset prefilter)
#
# Cutover to `on` as the default is PR A4, gated on the soak. Keep the .env comment in
# sync when that lands.
raw = ENV.fetch('TIER5_SIDECAR_SEARCH', 'shadow').to_s.strip.downcase

Rails.application.config.x.tier5_sidecar_search =
  case raw
  when 'on'          then :on
  when 'off'         then :off
  when 'shadow', ''  then :shadow
  else
    Rails.logger&.warn("[tier5_sidecar_search] unknown TIER5_SIDECAR_SEARCH=#{raw.inspect}; defaulting to shadow")
    :shadow
  end
