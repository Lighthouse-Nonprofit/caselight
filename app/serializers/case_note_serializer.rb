class CaseNoteSerializer < ActiveModel::Serializer
  attributes :attendee, :meeting_date, :assessment_id, :id, :created_at, :updated_at

  # AMS 0.10: nested collection via has_many + serializer (was a custom method using the removed
  # ActiveModel::ArraySerializer).
  has_many :case_note_domain_groups, serializer: CaseNoteDomainGroupSerializer
end
