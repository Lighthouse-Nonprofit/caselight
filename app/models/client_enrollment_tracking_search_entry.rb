# frozen_string_literal: true

# POAM-024 — search-entry sidecar rows for ClientEnrollmentTracking#properties. See PropertiesSearchEntry.
class ClientEnrollmentTrackingSearchEntry < PropertiesSearchEntry
  belongs_to :client_enrollment_tracking

  encrypts :value, deterministic: { fixed: false }
end
