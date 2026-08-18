class ProgramStream < ActiveRecord::Base
  FORM_BUILDER_FIELDS = ['enrollment', 'exit_program'].freeze

  has_many   :domain_program_streams, dependent: :destroy
  has_many   :domains, through: :domain_program_streams
  has_many   :agency_program_streams, dependent: :destroy # D1: partner agencies
  has_many   :agencies, through: :agency_program_streams
  has_many   :client_enrollments, dependent: :restrict_with_error
  has_many   :clients, through: :client_enrollments
  has_many   :trackings, dependent: :destroy
  has_many   :leave_programs

  has_paper_trail

  # BS5-Q3: reject NEW blank-name tracking rows — the form's JS pre-adds an empty template
  # row that always submits; two blank names hit the (name, program_stream_id) unique index
  # -> RecordNotUnique -> every draft save re-rendered :new (live bug, reproduced on dev).
  accepts_nested_attributes_for :trackings, allow_destroy: true,
                                reject_if: proc { |attrs| attrs['name'].blank? && attrs['id'].blank? }

  include FormBuilderFieldTypes # D5: server-side type allowlist

  # Owner-set lifecycle (distinct from `completed`, the internal config-readiness flag):
  # pending = set up, not yet running; active = currently running; completed = ran, no longer running.
  LIFECYCLE_STATUSES = %w[pending active completed].freeze

  validates :name, presence: true
  validates :name, uniqueness: true
  validates :status, inclusion: { in: LIFECYCLE_STATUSES }

  scope :lifecycle_active,    -> { where(status: 'active') }
  scope :lifecycle_pending,   -> { where(status: 'pending') }
  scope :lifecycle_completed, -> { where(status: 'completed') }
  validate  :form_builder_field_uniqueness
  validate  -> { validate_field_types_of(:enrollment, enrollment) }, if: -> { enrollment.present? }
  validate  -> { validate_field_types_of(:exit_program, exit_program) }, if: -> { exit_program.present? }

  # validate  :validate_remove_enrollment_field, :validate_remove_exit_program_field, if: -> { id.present? }

  after_save :set_program_completed

  scope  :ordered,     ->         { order(Arel.sql('lower(name) ASC')) }
  scope  :complete,    ->         { where(completed: true) }
  scope  :ordered_by,  ->(column) { order(column) }
  scope  :name_like,   ->(value)  { where(name: value) }

  # `filter` cannot be a scope on Ruby 2.6+: ActiveRecord::Relation now defines #filter
  # (an Enumerable alias for select), so `scope :filter` raises a dangerous-name ArgumentError
  # at class load. A class method preserves ProgramStream.filter(value) and matches the
  # `def self.filter` pattern already used in Client and Task.
  def self.filter(value)
    where(id: value)
  end

  def self.inactive_enrollments(client)
    joins(:client_enrollments).where("client_id = ? AND client_enrollments.created_at = (SELECT MAX(client_enrollments.created_at) FROM client_enrollments WHERE client_enrollments.program_stream_id = program_streams.id AND client_enrollments.client_id = #{client.id}) AND client_enrollments.status = 'Exited' ", client.id).ordered
  end

  def self.active_enrollments(client)
    joins(:client_enrollments).where("client_id = ? AND client_enrollments.created_at = (SELECT MAX(client_enrollments.created_at) FROM client_enrollments WHERE client_enrollments.program_stream_id = program_streams.id AND client_enrollments.client_id = #{client.id}) AND client_enrollments.status = 'Active' ", client.id).ordered
  end

  def self.without_status_by(client)
    ids = includes(:client_enrollments).where(client_enrollments: { client_id: client.id }).order('client_enrollments.status ASC', :name).distinct.collect(&:id)
    where.not(id: ids).ordered
  end

  # BS5-Q3 (latent since the Rails 4.2->5 rung, same as Tracking#fields=): the form posts
  # the three jsonb attributes as JSON-encoded strings; Rails 5+ stopped parsing String
  # assignment, so the `.map` in form_builder_field_uniqueness 500'd and
  # set_program_completed's `.empty?` checks ran against Strings. Parse at the boundary;
  # invalid JSON keeps the raw value (matching the old cast's failure mode).
  %w[enrollment exit_program rules].each do |attr|
    define_method("#{attr}=") do |value|
      if value.is_a?(String)
        value = begin
          ActiveSupport::JSON.decode(value)
        rescue StandardError
          value
        end
      end
      super(value)
    end
  end

  def form_builder_field_uniqueness
    errors_massage = []
    FORM_BUILDER_FIELDS.each do |field|
      labels = []
      next unless send(field.to_sym).present?
      send(field.to_sym).map{ |obj| labels << obj['label'] }
      errors_massage << (errors.add field.to_sym, "Fields duplicated!") unless (labels.uniq.length == labels.length)
    end
    errors_massage
  end

  # def validate_remove_enrollment_field
  #   return unless enrollment_changed?
  #   error_fields = []
  #   properties = client_enrollments.pluck(:properties).select(&:present?)
  #   properties.each do |property|
  #     field_remove = enrollment_change.first - enrollment_change.last
  #     field_remove.each do |field|
  #       label_name = property[field['label']]
  #       error_fields << field['label'] if label_name.present?
  #     end
  #   end
  #   return unless error_fields.present?
  #   error_message = "#{error_fields.uniq.join(', ')} #{I18n.t('cannot_remove_or_update')}"
  #   errors.add(:enrollment, "#{error_message}")
  #   errors.add(:tab, '3')
  # end

  # def validate_remove_exit_program_field
  #   return unless exit_program_changed?
  #   error_fields = []
  #   properties = leave_programs.pluck(:properties).select(&:present?)
  #   properties.each do |property|
  #     field_remove = exit_program_change.first - exit_program_change.last
  #     field_remove.each do |field|
  #       label_name = property[field['label']]
  #       error_fields << field['label'] if label_name.present?
  #     end
  #   end
  #   return unless error_fields.present?
  #   error_message = "#{error_fields.uniq.join(', ')} #{I18n.t('cannot_remove_or_update')}"
  #   errors.add(:exit_program, "#{error_message}")
  #   errors.add(:tab, '5')
  # end

  def last_enrollment
    client_enrollments.last
  end

  def number_available_for_client
    quantity - client_enrollments.active.size
  end

  def enroll?(client)
    enrollments = client_enrollments.enrollments_by(client).order(:created_at)
    (enrollments.present? && enrollments.first.status == 'Exited') || enrollments.empty?
  end

  def is_used?
    client_enrollments.active.present?
  end

  def has_program_exclusive?
    program_exclusive.any?
  end

  def has_mutual_dependence?
    mutual_dependence.any?
  end

  def has_rule?
    rules.present?
  end

  private

  def set_program_completed
    return update_columns(completed: false) if (enrollment.empty? || exit_program.empty? || trackings.empty? || trackings.pluck(:name).include?('') || trackings.pluck(:fields).include?([])) && !tracking_required
    update_columns(completed: true)
  end

  def enrollment_errors_message
    properties = client_enrollments.pluck(:properties).select(&:present?)
    error_fields(properties, enrollment_change).join(', ')
  end

  def tracking_errors_message
    properties = trackings.pluck(:properties).select(&:present?)
    error_fields(properties, tracking_change).join(', ')
  end

  def exit_program_errors_message
    properties = leave_programs.pluck(:properties).select(&:present?)
    error_fields(properties, exit_program_change).join(', ')
  end

  def error_fields(properties, column_change)
    error_fields = []
    properties.each do |property|
      field_remove = column_change.first - column_change.last
      field_remove.map{ |f| error_fields << f['label'] if property[f['label']].present? }
    end
    error_fields.uniq
  end
end
