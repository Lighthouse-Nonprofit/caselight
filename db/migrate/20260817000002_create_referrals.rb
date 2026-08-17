# Pre-migration batch, PR 4 — referrals OUT. Distinct from ReferralSource (referrals IN — a
# lookup of where clients come from). A Referral is a per-client outbound referral: the business
# or partner a client was sent TO (employment, housing, legal, medical, …), who made it, its
# status, and the outcome. reason/outcome are freeform narrative → encrypted at rest (SC-28),
# mirroring ProgressNote; the structured columns stay plaintext for listing/filtering.
class CreateReferrals < ActiveRecord::Migration[8.0]
  def change
    create_table :referrals do |t|
      t.references :client, null: false, foreign_key: true
      t.references :user,   foreign_key: true            # staff who made the referral (nullable)
      t.string  :organization_name, null: false, default: ''
      t.string  :referral_type,     default: ''          # Employment / Housing / Legal / …
      t.string  :contact_name,      default: ''
      t.string  :contact_phone,     default: ''
      t.string  :contact_email,     default: ''
      t.date    :referred_on
      t.string  :status,            default: 'Pending'   # Pending / Accepted / Declined / Completed
      t.date    :outcome_on
      t.text    :reason                                  # encrypted (non-deterministic)
      t.text    :outcome                                 # encrypted (non-deterministic)
      t.timestamps
    end

    add_index :referrals, :status
  end
end
