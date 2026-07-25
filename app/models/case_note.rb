class CaseNote < ActiveRecord::Base
  belongs_to :client
  belongs_to :assessment
  has_many   :case_note_domain_groups, dependent: :destroy
  has_many   :domain_groups, through: :case_note_domain_groups

  validates :meeting_date, :attendee, presence: true

  has_paper_trail

  # UX round 3 (D1/R7): unselected/blank domain sections never persist. Historically EVERY
  # case note saved one blank CaseNoteDomainGroup row per DomainGroup (populate_notes builds
  # them all; there was no reject_if). A row with an id is always accepted (deselecting a
  # filled section on edit only hides it — its inputs are disabled so nothing submits and the
  # row is left untouched; hiding never deletes).
  accepts_nested_attributes_for :case_note_domain_groups, reject_if: lambda { |attrs|
    attrs['id'].blank? && attrs['note'].blank? &&
      Array(attrs['task_ids']).reject(&:blank?).empty? &&
      Array(attrs['attachments']).reject(&:blank?).empty?
  }

  scope :most_recents, -> { order(created_at: :desc) }

  before_create :set_assessment

  # Idempotent (D1): edit + validation re-renders call this on a note that already has rows —
  # build sections only for the domain groups that lack one.
  def populate_notes
    existing = case_note_domain_groups.map(&:domain_group_id)
    DomainGroup.all.each do |dg|
      case_note_domain_groups.build(domain_group_id: dg.id) unless existing.include?(dg.id)
    end
  end

  def complete_tasks(params)
    (params || {}).each do |_index, param|
      case_note_domain_group = case_note_domain_groups.find_by(domain_group_id: param[:domain_group_id])
      next if case_note_domain_group.nil? # D1: section rejected as blank / not submitted
      task_ids = param[:task_ids] || []
      case_note_domain_group.tasks = Task.where(id: task_ids)
      case_note_domain_group.tasks.set_complete
      case_note_domain_group.save
    end
  end

  private

  def set_assessment
    self.assessment = client.assessments.latest_record
  end
end
