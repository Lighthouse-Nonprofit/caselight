# frozen_string_literal: true

module Reports
  # Counting layer for ENCRYPTED properties (enrollment/tracking/exit/custom forms).
  #
  # The properties column is non-deterministically encrypted — SQL can never GROUP
  # BY it. The queryable path is the Tier-5 sidecar (*SearchEntry: plaintext
  # field_label + deterministically-encrypted value): enumerate the possible values
  # from the PLAINTEXT field definitions (trackings.fields / program_streams
  # .enrollment jsonb / custom_fields.fields), then issue ONE indexed equality
  # COUNT per value. Values absent from the enumeration are invisible here — pair
  # with the field definition, never with a ciphertext scan.
  class ValueCounts
    # owner_scope: a relation of a PropertiesSearchable model (ClientEnrollment,
    # ClientEnrollmentTracking, LeaveProgram, CustomFieldProperty).
    # Returns { value => count } for every enumerated value (zeros kept).
    def self.count(owner_scope:, field_label:, values:, distinct_owners: false)
      entries = owner_scope.klass.properties_search_entry_class
      fk = owner_scope.klass.properties_search_entry_foreign_key
      ids = owner_scope.select(:id)
      values.index_with do |value|
        scope = entries.where(field_label: field_label, value: value.to_s, fk => ids)
        distinct_owners ? scope.distinct.count(fk) : scope.count
      end
    end

    # Owner ids whose field equals value — roster membership probes (cohort Term /
    # Site, Attendance = Present).
    def self.owner_ids(owner_scope:, field_label:, value:)
      entries = owner_scope.klass.properties_search_entry_class
      fk = owner_scope.klass.properties_search_entry_foreign_key
      entries.where(field_label: field_label, value: value.to_s,
                    fk => owner_scope.select(:id)).distinct.pluck(fk)
    end
  end
end
