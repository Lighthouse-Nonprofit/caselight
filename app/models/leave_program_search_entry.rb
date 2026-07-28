# frozen_string_literal: true

# POAM-024 — search-entry sidecar rows for LeaveProgram#properties. See PropertiesSearchEntry.
class LeaveProgramSearchEntry < PropertiesSearchEntry
  belongs_to :leave_program

  encrypts :value, deterministic: { fixed: false }
end
