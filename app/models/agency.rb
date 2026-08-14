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

  # A "campus" is a place represented as BOTH a school (attendance/academics) and a
  # site (program delivery) — same name, two kinds. `campus_twin` is the other-kind
  # record for the same place; `campus?` is true when it exists.
  def campus_twin
    return nil unless %w[school site].include?(kind)
    other = kind == 'school' ? 'site' : 'school'
    Agency.where(kind: other).where('lower(name) = ?', name.to_s.downcase).first
  end

  def campus?
    campus_twin.present?
  end

  # Make this place a full campus by creating its other-kind twin (idempotent —
  # returns the existing twin if there already is one).
  def ensure_campus_twin!
    return campus_twin if campus_twin
    other = kind == 'school' ? 'site' : 'school'
    Agency.create(name: name, description: description, kind: other)
  end
end
