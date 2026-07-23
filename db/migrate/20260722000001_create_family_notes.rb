# UX round 3 (B2) — household-level notes: a lightweight dated narrative attached to a Family
# (case notes / progress notes are client-only). `note` is text from day one: it carries
# non-deterministic ActiveRecord Encryption ciphertext (Tier-1 narrative discipline).
class CreateFamilyNotes < ActiveRecord::Migration[8.0]
  def change
    create_table :family_notes do |t|
      t.references :family, null: false, foreign_key: true
      t.date       :meeting_date, null: false
      t.string     :attendee
      t.text       :note
      t.references :user, foreign_key: true
      t.timestamps
    end
  end
end
