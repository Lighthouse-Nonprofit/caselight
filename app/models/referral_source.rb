class ReferralSource < ActiveRecord::Base
  # Investor UX round (2026-07): the association always existed from the Client side
  # (belongs_to + counter_cache); the inverse powers the index's linked-individuals column.
  has_many :clients

  has_paper_trail

  validates :name, presence: true, uniqueness: { case_sensitive: false }
end
