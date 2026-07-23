# UX round 3 (B3) — household alerts: "read this first" flags on a Family (wellness concerns,
# safety notes). Resolved, never deleted — the row is the audit trail. title/body carry
# non-deterministic ActiveRecord Encryption ciphertext (Tier-1 narrative discipline).
class CreateFamilyAlerts < ActiveRecord::Migration[8.0]
  def change
    create_table :family_alerts do |t|
      t.references :family, null: false, foreign_key: true
      t.string     :severity, null: false, default: 'caution'
      t.text       :title
      t.text       :body
      t.references :created_by, foreign_key: { to_table: :users }
      t.datetime   :resolved_at
      t.references :resolved_by, foreign_key: { to_table: :users }
      t.timestamps
    end
    add_index :family_alerts, %i[family_id resolved_at]
  end
end
