class LeaveProgram < ActiveRecord::Base
  belongs_to :client_enrollment
  belongs_to :program_stream
  has_many :form_builder_attachments, as: :form_buildable, dependent: :destroy

  # Phase 4 Tier 5 — field-level encryption at rest for program EXIT form values (FedRAMP SC-28,
  # SOC 2 C1.1). Per-client user-entered exit data (per ProgramStream#exit_program field defs).
  # NON-DETERMINISTIC; the exit advanced search is rewritten to in-Ruby decrypt-and-filter
  # (ExitProgramSqlBuilder + properties_by below). jsonb widened to :text; `attribute :properties, :json`
  # then `encrypts :properties` (=> Hash on read, envelope at rest). `.properties` stays a Hash for views/
  # validators; `pluck(:properties)` returns ciphertext (the program_stream.rb exit error helper was
  # switched off it). See custom_field_property.rb. Backfill: TIER=5.
  attribute :properties, :json
  encrypts  :properties

  validates :exit_date, presence: true

  accepts_nested_attributes_for :form_builder_attachments, reject_if: proc { |attributes| attributes['name'].blank? &&  attributes['file'].blank? }

  after_create :set_client_status

  has_paper_trail

  scope :find_by_program_stream_id, -> (value) { where(program_stream_id: value) }

  validate do |obj|
    CustomFormPresentValidator.new(obj, 'program_stream', 'exit_program').validate
    CustomFormNumericalityValidator.new(obj, 'program_stream', 'exit_program').validate
    CustomFormEmailValidator.new(obj, 'program_stream', 'exit_program').validate
  end

  # Phase 4 Tier 5 — REWRITTEN to in-Ruby decrypted-Hash extraction (was raw `properties -> 'value'`).
  # O(n)-decrypt over the scoped relation. See custom_field_property.rb#properties_by.
  def self.properties_by(value)
    all.map { |record| record.properties[value] }.select(&:present?)
  end

  def set_client_status
    self.client_enrollment.update_columns(status: 'Exited')

    client = Client.find(self.client_enrollment.client_id)
    if client.cases.current.nil? && client.client_enrollments.active.empty?
      client.update(status: 'Referred')
    end
  end

  def get_form_builder_attachment(value)
    form_builder_attachments.find_by(name: value)
  end
end
