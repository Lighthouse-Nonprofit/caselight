# frozen_string_literal: true

# POAM-024 — search-entry sidecar rows for CustomFieldProperty#properties. See PropertiesSearchEntry.
class CustomFieldPropertySearchEntry < PropertiesSearchEntry
  belongs_to :custom_field_property

  encrypts :value, deterministic: { fixed: false }
end
