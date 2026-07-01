# frozen_string_literal: true

module AdvancedSearches
  # POAM-004 Unit 2 (CRITICAL / live RCE). The advanced-search form posts custom_form_selected and
  # program_selected as bracketed integer-id strings built by JS, e.g. "[8,12,15]". These were fed
  # straight to Kernel#eval on a RAW request param -> arbitrary Ruby execution. Parse a strict
  # Integer array instead: "[8,12,15]" is valid JSON -> [8,12,15]; anything non-array / non-integer /
  # malformed -> [] (fail-safe empty selection, identical downstream to "nothing selected"). Never evals.
  module IdList
    module_function

    def parse(raw)
      Array(JSON.parse(raw.to_s)).map { |x| Integer(x) }
    rescue JSON::ParserError, TypeError, ArgumentError
      []
    end
  end
end
