# UX round 3 (B2) — a household-level note: dated narrative attached to the Family, written by
# staff (CaseNote/ProgressNote are client-only; household facts that belong to no single member
# live here). Deliberately lightweight — no assessment-domain machinery.
class FamilyNote < ActiveRecord::Base
  belongs_to :family
  belongs_to :user, optional: true

  # Tier-1 narrative PII: non-deterministic ciphertext at rest; paper_trail must never see the
  # plaintext (skip + RedactedUpdateVersions = values-free who/when versions). The reflective
  # paper_trail_redaction_spec drift-guards this pairing.
  has_paper_trail skip: %i[note]
  include RedactedUpdateVersions

  encrypts :note

  validates :meeting_date, presence: true
  validates :note, presence: true

  scope :most_recents, -> { order(meeting_date: :desc, created_at: :desc) }
end
