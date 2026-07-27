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
  # (assessment_domains) inherit via ad.domain. Vocabulary + validation + scopes live in the
  # shared Sensitizable concern (extracted 2026-07-26 — the old FOLLOW-UP here).
  include Sensitizable

  validates :domain_group, presence: true
  validates :name, :identity, presence: true, uniqueness: { case_sensitive: false }

  default_scope { order('domain_group_id ASC, name ASC') }

  scope :assessment_domains_by_assessment_id, ->(id) { joins(:assessment_domains).where('assessment_domains.assessment_id = ?', id) }

  # Rails 7.1 requires every enum to be backed by a DB column or an explicit attribute type;
  # domain_score_colors is a virtual color-mapping lookup (no column), so declare its type.
  # Positional form required: Rails 8.0 REMOVED the `enum name: {}` keyword syntax (raises at load).
  attribute :domain_score_colors, :string
  enum :domain_score_colors, { danger: 'Red', warning: 'Yellow', info: 'Blue', primary: 'Green' }
end
