# Pre-migration batch, PR 4 — a referral OUT (a client sent to an outside business/partner).
# Distinct from ReferralSource (the referral-IN lookup). Per-client, owned record (cascades
# with the client). Authorization mirrors Task: a broad `can :manage, Referral` per role, with
# the client scoping enforced by the nested controller's accessible_by find_client.
class Referral < ActiveRecord::Base
  belongs_to :client
  belongs_to :user, optional: true   # staff who made the referral

  TYPES = ['Employment', 'Housing', 'Legal', 'Medical / Health', 'Mental health',
           'Education / ESL', 'Benefits / Public assistance', 'Financial / Banking',
           'Childcare', 'Transportation', 'Food', 'Immigration', 'Other'].freeze
  STATUSES = %w[Pending Accepted Declined Completed].freeze
  OPEN_STATUSES = %w[Pending Accepted].freeze

  # Freeform narrative can carry client PII → encrypt at rest (SC-28), like ProgressNote.
  # NON-DETERMINISTIC: neither column is ever ORDER BY'd / WHERE'd / plucked (the indexes and
  # the manage-list filter ride the plaintext `status` column only). Keep them out of the
  # paper_trail payload so version history is not a masking-bypass channel.
  has_paper_trail skip: %i[reason outcome]
  encrypts :reason
  encrypts :outcome

  validates :organization_name, presence: true
  validates :status, inclusion: { in: STATUSES }

  scope :recent, -> { order(Arel.sql('referred_on DESC NULLS LAST'), created_at: :desc) }
  scope :open,   -> { where(status: OPEN_STATUSES) }
  scope :closed, -> { where.not(status: OPEN_STATUSES) }

  def open?
    OPEN_STATUSES.include?(status)
  end
end
