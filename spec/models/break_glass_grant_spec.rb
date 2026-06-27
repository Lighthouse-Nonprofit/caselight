# frozen_string_literal: true
require 'rails_helper'

# Phase 5.4 — BreakGlassGrant model. Runs in the test tenant where the break_glass_grants table
# (from the migration) exists.
RSpec.describe BreakGlassGrant, type: :model do
  let(:user)   { create(:user) }
  let(:client) { create(:client) }

  def grant(attrs = {})
    BreakGlassGrant.create!({
      user:                 user,
      custom_formable_type: 'Client',
      custom_formable_id:   client.id,
      custom_field_id:      nil,
      reason:               'Imminent welfare check',
      expires_at:           Time.current + 1.hour
    }.merge(attrs))
  end

  describe 'validations' do
    it 'requires a reason (mandatory justification)' do
      g = BreakGlassGrant.new(user: user, custom_formable_type: 'Client', custom_formable_id: client.id, expires_at: 1.hour.from_now)
      expect(g).not_to be_valid
      expect(g.errors[:reason]).to be_present
    end

    it 'rejects an unknown custom_formable_type' do
      g = BreakGlassGrant.new(user: user, custom_formable_type: 'Nope', custom_formable_id: 1, reason: 'x', expires_at: 1.hour.from_now)
      expect(g).not_to be_valid
      expect(g.errors[:custom_formable_type]).to be_present
    end
  end

  describe '.active' do
    it 'includes a live grant and excludes an expired one' do
      live    = grant(expires_at: 30.minutes.from_now)
      expired = grant(expires_at: 1.minute.ago)
      expect(BreakGlassGrant.active).to include(live)
      expect(BreakGlassGrant.active).not_to include(expired)
    end
  end

  describe '.active_for?' do
    it 'is true with a live grant' do
      grant(expires_at: 30.minutes.from_now)
      expect(BreakGlassGrant.active_for?(user, client)).to be(true)
    end
    it 'is false once expired' do
      grant(expires_at: 1.minute.ago)
      expect(BreakGlassGrant.active_for?(user, client)).to be(false)
    end
    it 'is false for a different user' do
      grant(expires_at: 30.minutes.from_now)
      expect(BreakGlassGrant.active_for?(create(:user), client)).to be(false)
    end
    it 'fails closed (false) if the table is missing' do
      allow(BreakGlassGrant).to receive(:for_user_and_record).and_raise(ActiveRecord::StatementInvalid, 'relation does not exist')
      expect(BreakGlassGrant.active_for?(user, client)).to be(false)
    end
  end

  describe '.active_form_ids_for' do
    it 'returns the unlocked custom_field_ids for form-scoped grants' do
      grant(custom_field_id: 7,  expires_at: 30.minutes.from_now)
      grant(custom_field_id: 11, expires_at: 30.minutes.from_now)
      expect(BreakGlassGrant.active_form_ids_for(user, client)).to match_array([7, 11])
    end
    it 'returns the :all sentinel for a record-wide (nil custom_field_id) grant' do
      grant(custom_field_id: nil, expires_at: 30.minutes.from_now)
      expect(BreakGlassGrant.active_form_ids_for(user, client)).to eq([:all])
    end
    it 'returns [] when there is no active grant' do
      grant(custom_field_id: 7, expires_at: 1.minute.ago)
      expect(BreakGlassGrant.active_form_ids_for(user, client)).to eq([])
    end
    it 'fails closed ([]) if the table is missing' do
      allow(BreakGlassGrant).to receive(:for_user_and_record).and_raise(ActiveRecord::StatementInvalid, 'relation does not exist')
      expect(BreakGlassGrant.active_form_ids_for(user, client)).to eq([])
    end
  end
end
