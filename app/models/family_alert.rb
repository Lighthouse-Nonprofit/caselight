# UX round 3 (B3) — a household alert: "read this first" information that must reach anyone
# opening the household or one of its members (wellness concerns, safety notes). Alerts are
# RESOLVED, never deleted — the record is the audit trail of who raised and cleared what.
class FamilyAlert < ActiveRecord::Base
  SEVERITIES = %w[notice caution critical].freeze

  belongs_to :family
  belongs_to :created_by,  class_name: 'User', optional: true
  belongs_to :resolved_by, class_name: 'User', optional: true

  # Tier-1 narrative PII (same pairing as FamilyNote; drift-guarded reflectively).
  has_paper_trail skip: %i[title body]
  include RedactedUpdateVersions

  encrypts :title
  encrypts :body

  validates :title, presence: true
  validates :severity, inclusion: { in: SEVERITIES }

  scope :active,       -> { where(resolved_at: nil) }
  scope :resolved,     -> { where.not(resolved_at: nil) }
  scope :most_recents, -> { order(created_at: :desc) }

  def active?
    resolved_at.nil?
  end

  def resolve!(user)
    update!(resolved_at: Time.current, resolved_by: user)
  end
end
