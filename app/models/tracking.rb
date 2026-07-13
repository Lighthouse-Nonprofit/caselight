class Tracking < ActiveRecord::Base
  FREQUENCIES = ['Daily', 'Weekly', 'Monthly', 'Yearly'].freeze
  belongs_to :program_stream
  has_many :client_enrollment_trackings, dependent: :restrict_with_error
  has_many :client_enrollments, through: :client_enrollment_trackings

  has_paper_trail

  validates :name, uniqueness: { scope: :program_stream_id }

  validate :form_builder_field_uniqueness
  validate :validate_remove_field, if: -> { id.present? }

  default_scope { order(:created_at) }

  # BS5-Q3 (latent since the Rails 4.2->5 rung): the program-stream form posts `fields`
  # as ONE JSON-encoded string; Rails 4.2's jsonb type parsed String assignment, Rails 5+
  # only parses on DB deserialize — so every tracking row 500'd in the validation below
  # (`fields.map` on a String). Restore the parse at the attribute boundary; invalid JSON
  # keeps the raw value (matching the old cast's failure mode).
  def fields=(value)
    if value.is_a?(String)
      value = begin
        ActiveSupport::JSON.decode(value)
      rescue StandardError
        value
      end
    end
    super(value)
  end

  def form_builder_field_uniqueness
    return unless fields.present?
    labels = fields.map{ |obj| obj['label'] }
    (errors.add :fields, "Fields duplicated!") unless (labels.uniq.length == labels.length)
  end

  def validate_remove_field
    return unless fields_changed?
    error_translation = I18n.t('cannot_remove_or_update')
    error_fields = []
    properties = client_enrollment_trackings.pluck(:properties).select(&:present?)

    properties.each do |property|
      field_remove = fields_change.first - fields_change.last
      field_remove.map{ |f| error_fields << f['label'] if property[f['label']].present? }
    end

    return unless error_fields.present?
    errors.add(:fields, "#{error_fields.uniq.join(', ')} #{error_translation}")
    errors.add(:tab, 4)
  end

  def is_used?
    client_enrollment_trackings.present?
  end
end
