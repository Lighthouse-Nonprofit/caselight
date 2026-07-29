# frozen_string_literal: true

# POAM-024 — abstract base for the four Tier-5 search-entry sidecar models
# (CustomFieldPropertySearchEntry / ClientEnrollmentSearchEntry / ClientEnrollmentTrackingSearchEntry /
# LeaveProgramSearchEntry). One row per (owner record, field_label, value element) of the owner's
# decrypted `.properties` Hash, kept in lock-step by PropertiesSearchable's diff-sync.
#
# `value` is encrypted DETERMINISTICALLY — same plaintext, same ciphertext — which is the whole point:
# `where(value: v)` becomes an indexed ciphertext-equality probe (ExtendedDeterministicQueries handles
# current+previous schemes, exactly like the Tier-3/4 name/email columns). NO hand-rolled HMAC: this
# rides the existing AR-Encryption key set, so the future KMS key migration and any key rotation treat
# these rows like every other deterministic column — no bespoke custody or rebuild trap. Accepted
# leakage (same class as Tier 3/4 deterministic): equality classes + per-field cardinality are visible
# to a DB-level adversary; field labels are plaintext BY DESIGN (they already sit in plaintext in
# custom_fields.fields / program_streams.enrollment+exit_program / trackings.fields).
#
# A NULL `value` is a PRESENCE MARKER (owner key present holding JSON null or []) — it satisfies the
# presence-EXISTS side of not_equal / is_not_empty while matching no equality probe.
#
# These rows are DERIVED data: `rake properties_search:backfill` rebuilds them from the owners at any
# time. No has_paper_trail (values-free by design would still be churn; the owner models carry the
# audit trail), no validations beyond the DB constraints (field_label '' must stay representable for
# strict parity with Hash-key semantics).
class PropertiesSearchEntry < ApplicationRecord
  self.abstract_class = true

  # NB: the `encrypts :value, deterministic: { fixed: false }` declaration lives in EACH concrete
  # subclass, NOT here — AR Encryption resolves the declared attribute's type against the DECLARING
  # class's schema, and an abstract class has no table (declaring it here raises
  # ActiveRecord::TableNotSpecified at first query). Keep the four declarations in lock-step.
end
