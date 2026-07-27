# frozen_string_literal: true

# Sensitizable — Phase 5.2/5.2b (NIST AC-6): the shared per-record sensitivity vocabulary for the
# two masking units — CustomField (per-FORM, Phase 5.2) and Domain (per-assessment-template,
# Phase 5.2b). ONE row = ONE level, ordered LEAST -> MOST sensitive: standard = any authorized
# reader of the record; restricted = caseload/role-scoped readers; emergency_only = break-glass
# only. SensitivityPolicy owns the need-to-know matrix; the scopes serve it plus the
# classification rake. Extracted 2026-07-26 from byte-identical duplication in both models (the
# long-standing domain.rb FOLLOW-UP) so the vocabulary cannot drift. Qualified references like
# CustomField::SENSITIVITY_LEVELS keep resolving here through ancestor constant lookup.
module Sensitizable
  extend ActiveSupport::Concern

  SENSITIVITY_LEVELS  = %w[standard restricted emergency_only].freeze
  DEFAULT_SENSITIVITY = 'standard'.freeze

  included do
    # sensitivity is NOT NULL with a DB default; validate the vocabulary so an out-of-band level
    # (a rake typo, a future migration) is rejected at the model boundary.
    validates :sensitivity, presence: true, inclusion: { in: SENSITIVITY_LEVELS }

    scope :by_sensitivity, ->(level) { where(sensitivity: level) }
    scope :standard,       ->        { where(sensitivity: 'standard') }
    scope :restricted,     ->        { where(sensitivity: 'restricted') }
    scope :emergency_only, ->        { where(sensitivity: 'emergency_only') }
  end
end
