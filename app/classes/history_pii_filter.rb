# frozen_string_literal: true

# HistoryPiiFilter — Phase 6 (SC-28 / POAM-SC28-HIST part B).
#
# The Mongo history models snapshot full `record.attributes` hashes, which return DECRYPTED values
# for every Phase-4 `encrypts` column — making the shared history database a plaintext PII shadow
# copy of the per-tenant encrypted Postgres columns. This filter strips those attributes (plus
# credential/network metadata that never belonged in a history snapshot) before the snapshot is
# persisted. The history keeps ids / statuses / dates / association keys — its actual job.
#
# Derivation is at CALL time, so any future `encrypts` declaration drops out of new snapshots with
# no further edits here (unlike the paper_trail skip: lists, which must be literal — see
# RedactedUpdateVersions / paper_trail_redaction_spec for why).
#
# Shape-tolerant by design: history writers run inside after_save callbacks and already tolerate
# nil attribute hashes (`try(:attributes)`), so non-Hash input passes through untouched.
module HistoryPiiFilter
  # Values that are sensitive regardless of encryption status.
  EXTRA_DENYLIST = {
    'User' => %w[encrypted_password otp_secret otp_backup_codes tokens
                 reset_password_token unlock_token
                 current_sign_in_ip last_sign_in_ip].freeze
  }.freeze

  # The denylist for a class — public so the one-time scrub of PRE-EXISTING Mongo docs
  # (lib/tasks/history_redaction.rake, Phase 6 U4) derives its $unset paths from the SAME source.
  def self.scrub_keys_for(klass)
    Array(klass.try(:encrypted_attributes)).map(&:to_s) + EXTRA_DENYLIST.fetch(klass.name, [])
  end

  def self.scrub(klass, attrs)
    return attrs unless attrs.is_a?(Hash)

    denied = scrub_keys_for(klass)
    return attrs if denied.empty?

    attrs.except(*denied)
  rescue StandardError
    # Never raise into an after_save history writer. Fail CLOSED on content: if the denylist can't
    # be computed, an empty snapshot beats a plaintext one.
    attrs.is_a?(Hash) ? {} : attrs
  end
end
