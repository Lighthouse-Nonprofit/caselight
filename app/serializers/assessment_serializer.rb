class AssessmentSerializer < ActiveModel::Serializer
  attributes :id, :client_id, :created_at, :updated_at

  has_many :assessment_domains
  # AMS 0.10: nested collection via has_many + serializer (was a custom method using the removed
  # ActiveModel::ArraySerializer).
  has_many :case_notes, serializer: CaseNoteSerializer
end
