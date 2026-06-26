class Domain < ActiveRecord::Base
  belongs_to :domain_group, counter_cache: true

  has_many   :assessment_domains, dependent: :restrict_with_error
  has_many   :assessments, through: :assessment_domains
  has_many   :tasks, dependent: :restrict_with_error
  has_many   :domain_program_streams, dependent: :restrict_with_error
  has_many   :program_streams, through: :domain_program_streams

  has_paper_trail

  # Phase 5.2b (NIST AC-6): per-Domain sensitivity, the assessment-side mirror of the per-FORM
  # CustomField model. The masking unit is the Domain (assessment template); answers
  # (assessment_domains) inherit via ad.domain. Source of truth for the LEVELS vocabulary is
  # CustomField::SENSITIVITY_LEVELS — duplicated here only because no shared concern exists yet.
  # FOLLOW-UP: extract a Sensitizable concern (constants + inclusion validation + the four scopes)
  # and include it in both CustomField and Domain so the vocabulary cannot drift.
  SENSITIVITY_LEVELS  = %w[standard restricted emergency_only].freeze
  DEFAULT_SENSITIVITY = 'standard'.freeze

  validates :domain_group, presence: true
  validates :name, :identity, presence: true, uniqueness: { case_sensitive: false }
  validates :sensitivity, presence: true, inclusion: { in: SENSITIVITY_LEVELS }

  default_scope { order('domain_group_id ASC, name ASC') }

  scope :assessment_domains_by_assessment_id, ->(id) { joins(:assessment_domains).where('assessment_domains.assessment_id = ?', id) }

  scope :by_sensitivity, ->(level) { where(sensitivity: level) }
  scope :standard,       ->        { where(sensitivity: 'standard') }
  scope :restricted,     ->        { where(sensitivity: 'restricted') }
  scope :emergency_only, ->        { where(sensitivity: 'emergency_only') }

  # Rails 7.1 requires every enum to be backed by a DB column or an explicit attribute type;
  # domain_score_colors is a virtual color-mapping lookup (no column), so declare its type.
  attribute :domain_score_colors, :string
  enum domain_score_colors: { danger: 'Red', warning: 'Yellow', info: 'Blue', primary: 'Green' }
end
