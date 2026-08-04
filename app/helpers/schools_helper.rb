# frozen_string_literal: true

# S5 — the school surfaces follow the same roster policy as the reports
# (BaseReport#client_label, decision D12): a strategic overviewer reads
# leadership AGGREGATES but not person names, so per-person rows show the record
# id instead. Every other role sees names.
module SchoolsHelper
  def school_person_label(client)
    return '' if client.nil?
    return "##{client.id}" if current_user&.strategic_overviewer?
    client.name
  end
end
