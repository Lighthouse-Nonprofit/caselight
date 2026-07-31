# Data-task batch D5 (SECURITY) — the server-side allowlist for form-builder field types.
#
# Builder JSON (CustomField#fields, ProgramStream#enrollment/#exit_program, Tracking#fields)
# flows into `render "/shared/fields/#{field['type'].underscore}"` at data-entry time. Until
# now the ONLY restriction was client-side (formBuilder's disableFields) — a hand-posted
# type reached the partial-path interpolation unchecked. Every write now dies here unless
# the type is one the renderer actually ships.
module FormBuilderFieldTypes
  extend ActiveSupport::Concern

  # The renderer's whole vocabulary: app/views/shared/fields/_*.haml ('file' is
  # special-cased to the attachment partial at the render sites). Stored data carries
  # BOTH spellings — formBuilder emits hyphenated ('checkbox-group') while older
  # seeds/specs stored underscored ('checkbox_group') — and the renderer underscores
  # before resolving the partial, so both are the SAME partial. Normalize before
  # comparing (post-merge CI caught the hyphen-only list rejecting legitimate forms).
  ALLOWED_FIELD_TYPES = %w[text textarea number date select checkbox-group radio-group file].freeze
  ALLOWED_NORMALIZED  = ALLOWED_FIELD_TYPES.map { |t| t.tr('-', '_') }.freeze

  def self.allowed_type?(type)
    ALLOWED_NORMALIZED.include?(type.to_s.tr('-', '_'))
  end

  private

  # Call from a validate hook per JSON attribute. Tolerates non-Array values — the
  # presence/shape validations on each model own those complaints.
  def validate_field_types_of(attr_name, value)
    return unless value.is_a?(Array)

    value.each do |field|
      next unless field.is_a?(Hash)
      type = field['type'] || field[:type]
      next if FormBuilderFieldTypes.allowed_type?(type)

      errors.add(attr_name, "contains an unsupported field type: #{type.to_s.truncate(30).inspect}")
    end
  end
end
