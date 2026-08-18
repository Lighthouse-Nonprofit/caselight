# frozen_string_literal: true
require 'rails_helper'

# Owner ask (2026-08): admins can clear a lockout and reset another user's password.
RSpec.describe 'Admin user management', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin)  { create(:user, roles: 'admin') }
  let!(:target) { create(:user, roles: 'case worker') }
  before { sign_in admin }

  it 'unlocks a locked account' do
    target.lock_access!
    expect(target.reload.access_locked?).to be(true)
    patch user_unlock_path(target)
    expect(target.reload.access_locked?).to be(false)
  end

  it 'resets a password to a new temporary one and surfaces it once' do
    old_digest = target.encrypted_password
    patch user_reset_password_path(target)
    expect(target.reload.encrypted_password).not_to eq(old_digest)
    follow_redirect!
    expect(flash[:notice]).to match(/Temporary password/i)
  end
end
