class Agency < ActiveRecord::Base
  has_many :agency_clients
  has_many :clients, through: :agency_clients
  # D1: which programs this partner agency works with
  has_many :agency_program_streams, dependent: :destroy
  has_many :program_streams, through: :agency_program_streams
  has_paper_trail

  # Scoped to kind so a campus can be BOTH a school (attendance) and a site
  # (delivery) — same name, two kinds — while still blocking a duplicate within a kind.
  validates :name, presence: true, uniqueness: { case_sensitive: false, scope: :kind }

  def self.name_like(values = [])
    where('name iLIKE ANY ( array[?] )', values)
  end
end
