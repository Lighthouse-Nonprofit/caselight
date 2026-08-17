# Pre-migration batch, PR 4 — richer donor management. The Donor model carried only
# name/code/description (it doubled as a funder-attribution lookup for clients). The org
# asked for "a true donor management feature": contact + relationship + a lightweight giving
# summary maintained on the record (no separate gift ledger — a deliberate scope call).
class AddDonorManagementFields < ActiveRecord::Migration[8.0]
  def change
    change_table :donors, bulk: true do |t|
      t.string  :donor_type,        default: ''    # Individual / Foundation / Corporation / Government / Faith community / Other
      t.string  :status,            default: ''    # Prospect / Active / Lapsed
      t.string  :contact_name,      default: ''
      t.string  :email,             default: ''
      t.string  :phone,             default: ''
      t.text    :address,           default: ''
      t.string  :website,           default: ''
      t.string  :tax_id,            default: ''    # EIN / tax id (foundations, corporations)
      t.string  :preferred_contact, default: ''    # Email / Phone / Mail
      t.decimal :total_giving,      precision: 12, scale: 2, default: '0.0'
      t.date    :last_gift_on
      t.decimal :last_gift_amount,  precision: 12, scale: 2
    end
  end
end
