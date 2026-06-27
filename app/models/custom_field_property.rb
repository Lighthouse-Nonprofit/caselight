class CustomFieldProperty < ActiveRecord::Base
  mount_uploaders :attachments, CustomFieldPropertyUploader

  belongs_to :custom_formable, polymorphic: true
  belongs_to :custom_field

  has_many :form_builder_attachments, as: :form_buildable, dependent: :destroy

  # Phase 4 Tier 5 — field-level encryption at rest for the polymorphic CUSTOM-FORM value store
  # (FedRAMP SC-28, SOC 2 C1.1). This is THE highest-risk JSONB PII: arbitrary admin-defined fields
  # (names, DOBs, free text, dropdowns) for Client/Family/User/Partner. NON-DETERMINISTIC — the custom-form
  # advanced search is rewritten to in-Ruby decrypt-and-filter (ClientCustomFormSqlBuilder + properties_by
  # below), so no ciphertext-equality query is needed and a random per-value IV is safe.
  #
  # COMPOSITION (verified on activerecord-7.2.3.1): the column was widened jsonb -> :text
  # (20260625000004_change_tier5_properties_jsonb_to_text). `attribute :properties, :json` restores the
  # Hash<->JSON behaviour over the text column; `encrypts :properties` then wraps THAT type, so
  # serialize = JSON.dump-then-encrypt (=> base64 envelope String at rest) and load = decrypt-then-JSON.parse
  # (=> Ruby Hash on read). `record.properties` therefore STILL returns a Hash, so every view / validator /
  # decorator that reads it as a Hash keeps working unchanged. The ORDER matters: `attribute` BEFORE
  # `encrypts`. NB: `pluck(:properties)` now bypasses the attribute type and returns the ciphertext STRING —
  # all such call sites were rewritten to read the decrypted Hash (api/program_streams_controller,
  # api/custom_fields_controller, program_stream/tracking error helpers, and properties_by below). The
  # SEPARATE `attachments` jsonb column (CarrierWave mount_uploaders) is NOT encrypted here and was NOT
  # widened — out of Tier 5 scope. support_unencrypted_data=true tolerates not-yet-backfilled plaintext
  # JSON during the window; run `rake encryption:backfill TIER=5 CONFIRM=1` then `encryption:verify TIER=5`.
  attribute :properties, :json
  encrypts  :properties

  scope :by_custom_field, -> (value) { where(custom_field:  value) }
  scope :most_recents,    ->         { order('created_at desc') }

  # Phase 5.3 — sensitive-field READ enforcement (NIST AC). FAIL-CLOSED: nil user / empty set => `none`,
  # never the full relation. A FILTER over rows already CanCan-scoped by the caller; NOT a record-auth check.
  scope :visible_to, ->(user, break_glass: []) {
    ids = CustomFieldProperty.visible_custom_field_ids(user, break_glass: break_glass)
    ids.empty? ? none : where(custom_field_id: ids.to_a)
  }

  # Set<Integer> of custom_field_ids `user` may read. Thin delegate to the Phase 5.2 policy (KEYWORD
  # arg). nil user -> empty set (fail-closed). break_glass = already-concrete emergency_only ids.
  def self.visible_custom_field_ids(user, break_glass: [])
    return Set.new if user.nil?
    SensitivityPolicy.new(user, active_break_glass_form_ids: Array(break_glass)).visible_custom_field_ids
  end

  accepts_nested_attributes_for :form_builder_attachments, reject_if: proc { |attributes| attributes['name'].blank? &&  attributes['file'].blank? }

  has_paper_trail

  after_save :create_client_history, if: :client_form?

  # Validate the association (present whether or not it's persisted) rather than the FK id:
  # factory_bot 6's use_parent_strategy builds (doesn't save) associations, so a built record
  # has a custom_field but no custom_field_id yet. Equivalent at runtime.
  validates :custom_field, presence: true

  validate do |obj|
    CustomFormPresentValidator.new(obj, 'custom_field', 'fields').validate
    CustomFormNumericalityValidator.new(obj, 'custom_field', 'fields').validate
    CustomFormEmailValidator.new(obj, 'custom_field', 'fields').validate
  end

  def client_form?
    custom_formable_type == 'Client'
  end

  def get_form_builder_attachment(value)
    form_builder_attachments.find_by(name: value)
  end

  # Phase 4 Tier 5 — REWRITTEN from raw `select("... properties -> 'value' as field_properties")` to
  # in-Ruby decrypted-Hash extraction. The old SQL `-> 'value'` returned the jsonb sub-value (string or
  # array) per row; reading the decrypted .properties Hash with [value] returns the SAME object. Contract
  # preserved: an Array of field values with blanks removed (ClientGrid / ClientGridOptions map
  # format_properties_value over it). `self`/`all` is the already-scoped relation (callers chain
  # .properties_by on a where()). O(n)-decrypt over the scoped rows (was a single SQL select) — acceptable
  # at pilot volume.
  def self.properties_by(value)
    all.map { |record| record.properties[value] }.select(&:present?)
  end

  private

  def create_client_history
    ClientHistory.initial(custom_formable)
  end
end
