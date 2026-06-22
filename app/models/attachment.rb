class Attachment < ActiveRecord::Base
  mount_uploader :image, ImageUploader
  mount_uploader :file, FileUploader

  has_paper_trail # audit document add/change/delete (SECURITY.md audit trail)

  belongs_to :able_screening_question
  belongs_to :progress_note

  validates_processing_of :image

  validate :image_size_validation

  private

  def image_size_validation
    errors[:image] << 'should be less than 1MB' if image.size > 1.megabytes
  end
end
