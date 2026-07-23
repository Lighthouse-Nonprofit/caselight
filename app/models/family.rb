class Family < ActiveRecord::Base
  include EntityTypeCustomField
  FAMILY_TYPE = %w(emergency kinship foster inactive birth_family).freeze

  # Display-only US labels for the upstream family_type values (SLO4HOME vocabulary). The DB
  # values, scopes, and filter params keep the raw strings — this map is the single source for
  # every user-facing rendering (grids, cards, forms, dashboard, version history).
  TYPE_LABELS = {
    'birth_family' => 'Household',
    'emergency'    => 'Priority Intake',
    'foster'       => 'Sponsor Household',
    'inactive'     => 'Closed',
    'kinship'      => 'Active'
  }.freeze

  def self.type_label(value)
    TYPE_LABELS[value.to_s] || value.to_s.titleize
  end

  belongs_to :province, counter_cache: true

  has_many :cases, dependent: :restrict_with_error
  has_many :clients, through: :cases
  has_many :custom_field_properties, as: :custom_formable, dependent: :destroy
  has_many :family_notes, dependent: :destroy  # UX round 3 (B2) — household-level notes
  has_many :custom_fields, through: :custom_field_properties, as: :custom_formable

  # Phase 6 (SC-28 / POAM-SC28-HIST) — keep the encrypted PII columns out of version payloads
  # (who/when survives; before/after values for these fields do not). Literal list; drift-guarded
  # by paper_trail_redaction_spec.
  has_paper_trail skip: %i[caregiver_information case_history address]
  include RedactedUpdateVersions  # skipped-only edits still write a values-free who/when version

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
  encrypts :address  # Phase 4 Tier 2 — address PII (SC-28); address_like scope + FamilyGrid filter removed; string->text

  # "Household Size" (significant_family_member_count) is DERIVED from the demographic counts so it always
  # reflects the actual household (member_count = adults + children) instead of a manual figure that defaulted
  # to 1 and was never populated. Kept as a stored column (the serializer/grid/show read it directly); it is
  # recomputed on every save, and the manual form input was removed since it is now auto-maintained.
  before_save { self.significant_family_member_count = member_count }

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
