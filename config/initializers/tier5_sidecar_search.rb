# frozen_string_literal: true

# POAM-024 (PR A4 — CUTOVER, 2026-07-28) — read-path mode for the Tier-5 search-entry sidecar
# (PropertiesSearchEntry + AdvancedSearches::PropertiesFilter#apply). Two states since the
# cutover:
#
#   on  (DEFAULT) -> sidecar-served: the equality family (equal/not_equal/is_empty/
#                    is_not_empty — the only operators dropdown/radio/checkbox fields offer)
#                    is indexed SQL against the entry tables; contains/ordered/between run
#                    presence-prefiltered Ruby through the oracle-verified match?.
#   off           -> the legacy full O(n)-decrypt path — the KILL SWITCH, kept for one
#                    release (TIER5_SIDECAR_SEARCH=off in .env + restart).
#
# The A3 `shadow` mode (serve legacy, race the sidecar, log tier5_sidecar_shadow divergence
# events) retired at cutover with ZERO divergences across: the CI-pinned both-paths oracle
# matrix, a 15-search all-operator burst on dev, a 21-search burst on the pilot box, and the
# box's organic window since deploy. Shadow DID fire during the program — 5 events on a dev
# checkout that had migrated but not backfilled (sidecar_count=0 signature), which is the
# exact condition it existed to catch; bootstrap step 7d makes that impossible on a deployed
# box, and DEVELOPMENT.md documents the one-time dev backfill.
raw = ENV.fetch('TIER5_SIDECAR_SEARCH', 'on').to_s.strip.downcase

Rails.application.config.x.tier5_sidecar_search =
  case raw
  when 'off' then :off
  when 'on', '' then :on
  else
    Rails.logger&.warn("[tier5_sidecar_search] unknown TIER5_SIDECAR_SEARCH=#{raw.inspect}; defaulting to on")
    :on
  end
