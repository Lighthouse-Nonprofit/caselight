class ClientEnrollment < ActiveRecord::Base
  belongs_to :client
  belongs_to :program_stream

  has_many :client_enrollment_trackings, dependent: :destroy
  has_many :form_builder_attachments, as: :form_buildable, dependent: :destroy
  has_many :trackings, through: :client_enrollment_trackings
  has_one :leave_program, dependent: :destroy

  # Phase 4 Tier 5 — field-level encryption at rest for program-stream ENROLLMENT form values
  # (FedRAMP SC-28, SOC 2 C1.1). Per-client user-entered enrollment data (per ProgramStream#enrollment
  # field defs). NON-DETERMINISTIC; the enrollment advanced search is rewritten to in-Ruby decrypt-and-filter
  # (EnrollmentSqlBuilder + properties_by below). jsonb widened to :text; `attribute :properties, :json`
  # restores Hash<->JSON then `encrypts` wraps it (serialize=JSON+encrypt envelope; load=decrypt+JSON.parse =>
  # Hash). `.properties` stays a Hash for views/validators; `pluck(:properties)` now returns ciphertext
  # (the api/program_stream callers were switched off pluck). See custom_field_property.rb for the full
  # composition note. Backfill: `rake encryption:backfill TIER=5 CONFIRM=1` then `encryption:verify TIER=5`.
  attribute :properties, :json
  encrypts  :properties

  validates :enrollment_date, presence: true
  accepts_nested_attributes_for :form_builder_attachments, reject_if: proc { |attributes| attributes['name'].blank? &&  attributes['file'].blank? }

  has_paper_trail

  scope :enrollments_by,              ->(client)         { where(client_id: client) }
  scope :find_by_program_stream_id,   ->(value)          { where(program_stream_id: value) }
  scope :active,                      ->                 { where(status: 'Active') }
  scope :inactive,                    ->                 { where(status: 'Exited') }

  after_create :set_client_status
  after_destroy :reset_client_status

  validate do |obj|
    CustomFormPresentValidator.new(obj, 'program_stream', 'enrollment').validate
    CustomFormNumericalityValidator.new(obj, 'program_stream', 'enrollment').validate
    CustomFormEmailValidator.new(obj, 'program_stream', 'enrollment').validate
  end

  def active?
    status == 'Active'
  end

  def has_client_enrollment_tracking?
    client_enrollment_trackings.present?
  end

  # Phase 4 Tier 5 — REWRITTEN to in-Ruby decrypted-Hash extraction (was raw `properties -> 'value'`).
  # Returns the Array of field values (blanks removed); ClientGridOptions maps format_properties_value
  # over it. O(n)-decrypt over the scoped relation. See custom_field_property.rb#properties_by.
  def self.properties_by(value)
    all.map { |record| record.properties[value] }.select(&:present?)
  end

  def set_client_status
    client = Client.find self.client_id
    client_status = 'Active' unless client.cases.exclude_referred.currents.present?
    client.update(status: client_status) if client_status.present?
  end

  def get_form_builder_attachment(value)
    form_builder_attachments.find_by(name: value)
  end

  def reset_client_status
    client = Client.find(client_id)
    return if client.active_case? || client.client_enrollments.active.any?

    client.update(status: 'Referred')
  end
end
