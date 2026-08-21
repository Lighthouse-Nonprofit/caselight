class ProgressNoteType < ActiveRecord::Base
  # Bifurcated note families (OCA 2026-08): the flexible note is a CONTACT log entry, a CURRICULUM /
  # session narrative, or a GENERAL client note. Drives the grouped picker + the Notes-tab filter.
  CATEGORIES = %w[contact curriculum general].freeze

  # The two non-contact families each have a single canonical type row (the contact family has many).
  CURRICULUM_TYPE = 'Curriculum / Session'
  GENERAL_TYPE    = 'General note'

  # Display order + human labels for the family optgroups/headers.
  CATEGORY_LABELS = { 'contact' => 'Contact', 'curriculum' => 'Curriculum & Activity', 'general' => 'General' }.freeze

  has_many :progress_notes, dependent: :restrict_with_error

  has_paper_trail

  validates :note_type, presence: true, uniqueness: { case_sensitive: false }
  validates :category, inclusion: { in: CATEGORIES }

  scope :contact,    -> { where(category: 'contact') }
  scope :curriculum, -> { where(category: 'curriculum') }
  scope :general,    -> { where(category: 'general') }

  # Ordered [category, [types]] pairs for grouped selects/sections (empty families omitted).
  def self.grouped_by_category
    all_by_cat = all.group_by(&:category)
    CATEGORIES.filter_map do |cat|
      types = (all_by_cat[cat] || []).sort_by { |t| t.note_type.to_s.downcase }
      [CATEGORY_LABELS[cat], types] if types.any?
    end
  end

  def category_label
    CATEGORY_LABELS[category] || category.to_s.titleize
  end
end
