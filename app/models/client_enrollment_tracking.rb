class ClientEnrollmentTracking < ActiveRecord::Base
  belongs_to :client_enrollment
  belongs_to :tracking

  has_many :form_builder_attachments, as: :form_buildable, dependent: :destroy

  # Phase 4 Tier 5 — field-level encryption at rest for recurring TRACKING form values
  # (FedRAMP SC-28, SOC 2 C1.1). Date-stamped per-client user-entered tracking data (per Tracking#fields).
  # NON-DETERMINISTIC; the tracking advanced search is rewritten to in-Ruby decrypt-and-filter
  # (TrackingSqlBuilder + properties_by below). jsonb widened to :text; `attribute :properties, :json` then
  # `encrypts :properties` (=> Hash on read, envelope at rest). `.properties` stays a Hash for views/
  # validators; `pluck(:properties)` returns ciphertext (the tracking.rb / api callers were switched off it).
  # See custom_field_property.rb. Backfill: TIER=5.
  attribute :properties, :json
  encrypts  :properties

  # POAM-024 — deterministic search-entry sidecar (ClientEnrollmentTrackingSearchEntry); see
  # custom_field_property.rb / PropertiesSearchable.
  include PropertiesSearchable

  accepts_nested_attributes_for :form_builder_attachments, reject_if: proc { |attributes| attributes['name'].blank? &&  attributes['file'].blank? }

  # Phase 6 (SC-28 / POAM-SC28-HIST) — keep the Tier-5 encrypted properties out of version payloads.
  has_paper_trail skip: %i[properties]
  include RedactedUpdateVersions  # properties-only saves still write a values-free who/when version

  scope :ordered, -> { order(:created_at) }
  scope :enrollment_trackings_by, -> (tracking) { where(tracking_id: tracking) }

  validate do |obj|
    CustomFormPresentValidator.new(obj, 'tracking', 'fields').validate
    CustomFormNumericalityValidator.new(obj, 'tracking', 'fields').validate
    CustomFormEmailValidator.new(obj, 'tracking', 'fields').validate
  end

  # Phase 4 Tier 5 — REWRITTEN to in-Ruby decrypted-Hash extraction (was raw `properties -> 'value'`).
  # O(n)-decrypt over the scoped relation. See custom_field_property.rb#properties_by.
  def self.properties_by(value)
    all.map { |record| record.properties[value] }.select(&:present?)
  end

  def get_form_builder_attachment(value)
    form_builder_attachments.find_by(name: value)
  end
end
