# frozen_string_literal: true
require 'rails_helper'

RSpec.describe HistoryPiiFilter do
  describe '.scrub' do
    it 'removes every encrypted attribute for the class' do
      attrs = { 'id' => 1, 'given_name' => 'Secret', 'current_address' => '1 Main St',
                'status' => 'Referred', 'slug' => 'abc-1' }
      out = described_class.scrub(Client, attrs)
      expect(out.keys).to include('id', 'status', 'slug')
      expect(out.keys).not_to include('given_name', 'current_address')
    end

    it 'derives from encrypted_attributes at call time (covers all Client tiers)' do
      attrs = Client.encrypted_attributes.map { |a| [a.to_s, 'x'] }.to_h.merge('id' => 9)
      expect(described_class.scrub(Client, attrs)).to eq('id' => 9)
    end

    it 'removes User credential and network metadata via EXTRA_DENYLIST' do
      attrs = { 'id' => 2, 'email' => 'a@b.c', 'encrypted_password' => 'hash',
                'otp_secret' => 'x', 'otp_backup_codes' => %w[a b],
                'current_sign_in_ip' => '10.0.0.1', 'last_sign_in_ip' => '10.0.0.2',
                'reset_password_token' => 'tok', 'unlock_token' => 'tok2', 'tokens' => '{}',
                'roles' => 'case worker' }
      out = described_class.scrub(User, attrs)
      expect(out).to eq('id' => 2, 'roles' => 'case worker')
    end

    it 'is a no-op for classes with no encrypted attributes' do
      attrs = { 'id' => 3, 'name' => 'Agency X' }
      expect(described_class.scrub(Agency, attrs)).to eq(attrs)
    end

    it 'passes nil and non-Hash input through untouched' do
      expect(described_class.scrub(User, nil)).to be_nil
      expect(described_class.scrub(User, 'oops')).to eq('oops')
    end
  end
end
