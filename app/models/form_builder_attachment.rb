class FormBuilderAttachment < ActiveRecord::Base
  mount_uploaders :file, FormBuilderAttachmentUploader

  has_paper_trail # audit document add/change/delete (SECURITY.md audit trail)

  belongs_to :form_buildable, polymorphic: true

  validates :name, uniqueness: { scope: [:form_buildable_type, :form_buildable_id] }

  scope :find_by_form_buildable, -> (id, type) { where(form_buildable_id: id, form_buildable_type: type) }

  def self.file_by_name(value)
    find_by(name: value)
  end
end
