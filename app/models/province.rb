class Province < ActiveRecord::Base
  has_many :users
  has_many :families
  has_many :partner
  has_many :clients
  has_many :cases

  has_paper_trail

  scope :has_clients,  -> { joins(:clients).distinct }

  scope :birth_places, -> { joins('RIGHT JOIN clients ON clients.birth_province_id = Provinces.id').distinct }

  validates :name, presence: true, uniqueness: { case_sensitive: false }

  def removeable?
    families_count.zero? && partners_count.zero? && users_count.zero? && clients_count.zero? && cases_count.zero?
  end
end
