class Donor < ActiveRecord::Base
  has_many :clients, dependent: :restrict_with_error

  has_paper_trail

  # PR 4 — richer donor management (contact + relationship + a lightweight giving summary
  # maintained on the record; no separate gift ledger by design).
  TYPES    = ['Individual', 'Foundation', 'Corporation', 'Government', 'Faith community', 'Other'].freeze
  STATUSES = %w[Prospect Active Lapsed].freeze
  CONTACT_METHODS = %w[Email Phone Mail].freeze

  scope :has_clients, -> { joins(:clients).distinct }
  scope :active,      -> { where(status: 'Active') }

  validates :name, presence: true, uniqueness: { case_sensitive: false },               if: -> { code.blank? }
  validates :name, presence: true, uniqueness: { case_sensitive: false, scope: :code }, if: -> { code.present? }
  validates :code, uniqueness: { case_sensitive: false }
  validates :email, format: { with: URI::MailTo::EMAIL_REGEXP }, allow_blank: true
  validates :total_giving, :last_gift_amount,
            numericality: { greater_than_or_equal_to: 0 }, allow_nil: true
end
