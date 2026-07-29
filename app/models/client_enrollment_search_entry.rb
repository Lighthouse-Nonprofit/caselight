# frozen_string_literal: true

# POAM-024 — search-entry sidecar rows for ClientEnrollment#properties. See PropertiesSearchEntry.
class ClientEnrollmentSearchEntry < PropertiesSearchEntry
  belongs_to :client_enrollment

  encrypts :value, deterministic: { fixed: false }
end
