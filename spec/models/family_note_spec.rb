# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B2) — FamilyNote: household-level dated narrative. Encryption discipline follows
# the Tier-1 narrative columns (non-deterministic ciphertext at rest; paper_trail skip is
# drift-guarded reflectively by paper_trail_redaction_spec).
RSpec.describe FamilyNote, type: :model do
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  describe 'validations + associations' do
    it 'requires meeting_date and note' do
      note = FamilyNote.new
      expect(note).not_to be_valid
      expect(note.errors[:meeting_date]).to be_present
      expect(note.errors[:note]).to be_present
    end

    it 'belongs to a family and optionally an author' do
      note = create(:family_note, user: nil)
      expect(note.family).to be_present
      expect(note.user).to be_nil
    end
  end

  describe 'encryption at rest (SC-28)' do
    it 'declares note as an encrypted attribute' do
      expect(FamilyNote.encrypted_attributes).to include(:note)
    end

    it 'decrypts transparently on read but stores ciphertext in the raw column' do
      plaintext = 'Landlord dispute resolved; utilities transferred to the family.'
      note = create(:family_note, note: plaintext)

      expect(FamilyNote.find(note.id).note).to eq(plaintext)

      raw = raw_column(FamilyNote, note.id, :note)
      expect(raw).to be_present
      expect(raw).not_to eq(plaintext)
    end
  end

  describe '.most_recents' do
    it 'orders by meeting_date desc, then created_at desc' do
      family = create(:family)
      older  = create(:family_note, family: family, meeting_date: 2.weeks.ago.to_date)
      newer  = create(:family_note, family: family, meeting_date: Date.today)
      expect(family.family_notes.most_recents.to_a).to eq([newer, older])
    end
  end
end
