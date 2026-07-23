# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B3) — FamilyAlert: "read first" household flags. Resolve-not-delete semantics;
# Tier-1 narrative encryption on title/body.
RSpec.describe FamilyAlert, type: :model do
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  it 'requires a title and a known severity' do
    alert = FamilyAlert.new(family: create(:family))
    expect(alert).not_to be_valid
    expect(alert.errors[:title]).to be_present

    alert.title = 'Read first'
    alert.severity = 'apocalyptic'
    expect(alert).not_to be_valid
    expect(alert.errors[:severity]).to be_present
  end

  it 'encrypts title and body at rest' do
    expect(FamilyAlert.encrypted_attributes).to include(:title, :body)
    alert = create(:family_alert, title: 'Do not visit alone', body: 'Aggressive dog on premises.')
    expect(FamilyAlert.find(alert.id).title).to eq('Do not visit alone')
    expect(raw_column(FamilyAlert, alert.id, :title)).not_to eq('Do not visit alone')
    expect(raw_column(FamilyAlert, alert.id, :body)).not_to eq('Aggressive dog on premises.')
  end

  describe 'resolve!' do
    it 'moves the alert between the active and resolved scopes and stamps who/when' do
      alert = create(:family_alert)
      resolver = create(:user)
      expect(FamilyAlert.active).to include(alert)

      alert.resolve!(resolver)

      expect(alert.reload).not_to be_active
      expect(alert.resolved_by).to eq(resolver)
      expect(alert.resolved_at).to be_present
      expect(FamilyAlert.active).not_to include(alert)
      expect(FamilyAlert.resolved).to include(alert)
    end
  end
end
