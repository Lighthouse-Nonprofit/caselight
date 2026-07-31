# Data-task batch D1 — join: which programs a partner agency works with
# (domain_program_streams precedent).
class AgencyProgramStream < ActiveRecord::Base
  belongs_to :agency
  belongs_to :program_stream

  validates :program_stream_id, uniqueness: { scope: :agency_id }
end
