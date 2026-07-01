# frozen_string_literal: true

# SafeVersionValue -- POAM-004 Unit 2. Single audited replacement for the Kernel#eval calls that
# rebuilt a Ruby Hash/Array from a paper_trail changeset value in shared/version_type/*.haml.
#
# The eval'd value is a paper_trail changeset element (properties / fields / enrollment / exit_program).
# On live cases data (546 versions, 0 String occurrences) that element is ALREADY a deserialized
# Hash/Array -- Rails-typed changeset casting decodes the JSONB columns before the view sees it -- so
# the eval branch was dead and this parser is a NO-OP pass-through on the live path (byte-identical).
# When the element IS a String (legacy/defensive), it is parsed with the SAME JSON-then-YAML.safe_load
# ladder that SensitiveVersionScope#version_object_hash relies on. NEVER evaluates code; NEVER raises;
# returns nil on empty/unparseable input so the view's existing `next if values == '{}'` /
# `if values.present?` guards keep behaving exactly as before. A ruby-looking plain scalar string
# (e.g. "system('x')") is inert: JSON.parse fails, YAML.safe_load returns the raw STRING (never runs
# it); the caller uses `SafeVersionValue.parse(v) || v` and a `respond_to?(:each)` guard so a raw
# String can neither execute nor crash the view.
#
# This is the single source of truth for that ladder: SensitiveVersionScope delegates to it.
module SafeVersionValue
  module_function

  # Permitted classes for the YAML fallback -- the exact set the Phase-5.3 SensitiveVersionScope
  # permitted set covers real object_changes payloads with.
  PERMITTED = [Time, Date, ActiveSupport::TimeWithZone, ActiveSupport::TimeZone, Symbol, BigDecimal].freeze

  # Returns a deserialized Hash/Array (or the original non-String value), or nil.
  # nil / '' / '{}' / '[]' -> nil (matches the view's empty-guards); a String -> JSON.parse, then
  # YAML.safe_load(permitted_classes:) fallback; anything unparseable -> the raw String or nil.
  # NEVER raises, NEVER evals.
  def parse(raw)
    return nil if raw.nil?
    return raw unless raw.is_a?(String)
    s = raw.strip
    return nil if s.empty? || s == '{}' || s == '[]'
    begin
      JSON.parse(s)
    rescue JSON::ParserError
      begin
        YAML.safe_load(s, permitted_classes: PERMITTED, aliases: true)
      rescue StandardError
        nil
      end
    end
  end
end
