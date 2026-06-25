class Family < ActiveRecord::Base
  include EntityTypeCustomField
  FAMILY_TYPE = %w(emergency kinship foster inactive birth_family).freeze

  belongs_to :province, counter_cache: true

  has_many :cases, dependent: :restrict_with_error
  has_many :clients, through: :cases
  has_many :custom_field_properties, as: :custom_formable, dependent: :destroy
  has_many :custom_fields, through: :custom_field_properties, as: :custom_formable

  has_paper_trail

  validates :family_type, presence: true, inclusion: { in: FAMILY_TYPE }
  validates :code, uniqueness: { case_sensitive: false }, if: -> { code.present? }

  # Phase 4 Tier 1 — encrypt sensitive narrative PII at rest (SC-28, SOC 2 C1.1). NON-DETERMINISTIC,
  # so these columns are no longer searchable: the caregiver_information_like / case_history_like
  # scopes and the FamilyGrid filters/order that used them (app/grids/family_grid.rb) were removed in
  # this same change. caregiver_information is already `text`; case_history was `string`, widened to
  # `text` by db/migrate/20260624000005_change_family_case_history_to_text.rb (ciphertext overflows
  # the default varchar). Backfill with `rake encryption:backfill MODELS=Family` then `rake encryption:verify`.
  encrypts :caregiver_information
  encrypts :case_history

  scope :address_like,               ->(value) { where('address iLIKE ?', "%#{value}%") }
  scope :emergency,                  ->        { where(family_type: 'emergency') }
  scope :family_id_like,             ->(value) { where('code iLIKE ?', "%#{value}%") }
  scope :foster,                     ->        { where(family_type: 'foster')    }
  scope :kinship,                    ->        { where(family_type: 'kinship')   }
  scope :inactive,                   ->        { where(family_type: 'inactive')   }
  scope :birth_family,               ->        { where(family_type: 'birth_family')   }
  scope :name_like,                  ->(value) { where('name iLIKE ?', "%#{value}%") }
  scope :province_are,               ->        { joins(:province).pluck('provinces.name', 'provinces.id').uniq }
  scope :as_non_cases,               ->        { where.not(family_type: ['emergency', 'foster', 'kinship']) }

  def member_count
    male_adult_count.to_i + female_adult_count.to_i + male_children_count.to_i + female_children_count.to_i
  end

  def self.by_family_type(type)
    if type == 'emergency'
      emergency
    elsif type == 'kinship'
      kinship
    elsif type == 'foster'
      foster
    elsif type == 'inactive'
      inactive
    elsif type == 'birth_family'
      birth_family
    end
  end

  FAMILY_TYPE.each do |type|
    define_method "#{type}?" do
      family_type == type
    end
  end

  def is_case?
    emergency? || foster? || kinship?
  end
end
