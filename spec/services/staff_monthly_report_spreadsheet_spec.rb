require 'rails_helper'

# Phase 4 Tier 3 added an IN-RUBY name sort to StaffMonthlyReportSpreadsheet because users.first_name /
# last_name are now DETERMINISTICALLY encrypted — an SQL `.order(:first_name, :last_name)` would sort by
# opaque ciphertext (effectively random). This guards that the staff report orders by the DECRYPTED display
# name, case-insensitively. Previously this service had NO runnable coverage (the cron wiring lives in the
# excluded spec/schedule_spec.rb; the report logic itself was untested), so this also closes a CI gap.
RSpec.describe StaffMonthlyReportSpreadsheet, type: :model do
  describe '#sorted_by_name (Tier 3 in-memory sort over decrypted names)' do
    it 'orders users by decrypted display name (case-insensitive), not by encrypted ciphertext' do
      zoe = create(:user, first_name: 'Zoe', last_name: 'Adams')
      amy = create(:user, first_name: 'amy', last_name: 'Baker')
      bob = create(:user, first_name: 'Bob', last_name: 'Carter')

      relation = User.where(id: [zoe.id, amy.id, bob.id])
      sorted   = described_class.new.send(:sorted_by_name, relation)

      # amy / Bob / Zoe by name.downcase — a SQL ciphertext sort could not produce this order.
      expect(sorted.map(&:id)).to eq([amy.id, bob.id, zoe.id])
      expect(sorted.map(&:first_name)).to eq(%w[amy Bob Zoe])
    end

    it 'returns a plain Array (decrypted in Ruby), not a SQL-ordered relation' do
      create(:user, first_name: 'Solo', last_name: 'Person')
      result = described_class.new.send(:sorted_by_name, User.all)
      expect(result).to be_an(Array)
      expect(result).to all(be_a(User))
    end
  end
end
