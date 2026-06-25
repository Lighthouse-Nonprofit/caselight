# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 3 — MANDATORY auth-path regression specs for the DETERMINISTIC encryption of users.email
# (the Devise login identifier). The highest-risk part of Tier 3: a normalization mismatch between the
# WRITE-side and LOOKUP-side email handling silently breaks EVERY login.
#
# Why these are load-bearing:
#   * `encrypts :email, deterministic: true, downcase: true`. The deterministic ciphertext is what the
#     equality query in find_for_database_authentication compares against. downcase:true normalizes the
#     value BEFORE computing that ciphertext on BOTH write and query.
#   * SessionsController#create looks up the user with
#     `find_for_database_authentication(email: creds[:email].to_s.strip)` — it STRIPS but does NOT
#     downcase. So a mixed-case form submission ONLY matches the stored row because AR's downcase:true
#     normalizes the query value. If downcase:true were dropped, mixed-case logins silently fail.
#     The 'mixed-case + whitespace' example below is the guard that locks that in.
#   * MIGRATION-WINDOW NOTE (deploy runbook): under support_unencrypted_data=true a NOT-YET-BACKFILLED
#     plaintext email row will NOT match the deterministic equality query and that user cannot log in.
#     The email backfill (rake encryption:backfill TIER=3 CONFIRM=1) MUST run in the SAME deploy step as
#     adding `encrypts`, BEFORE anyone signs in. Users created post-deploy are encrypted on save (what
#     these specs exercise), so they are unaffected; existing rows depend on the backfill.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). MFA is opt-in (otp_required_for_login
# defaults false), so create(:user) signs in with email+password. Mirrors spec/requests/two_factor_spec.rb.
RSpec.describe 'Tier 3 encrypted-email login path (SC-28 / IA-2)', type: :request do
  include Devise::Test::IntegrationHelpers

  let(:password) { 'SecurePass123!' }

  # A protected page bounces unauthenticated requests to the login page, so this is a reliable
  # "am I signed in?" probe across the shared request-spec session (cf. two_factor_spec).
  def authenticated?
    get '/dashboards'
    !(response.redirect? && response.location.to_s.include?('/users/sign_in'))
  end

  describe 'sign-in with an encrypted email (no MFA)' do
    it 'signs in with the exact (stored, downcased) email + password' do
      user = create(:user, email: 'login.exact@example.org', password: password,
                           password_confirmation: password)
      post user_session_path, params: { user: { email: user.email, password: password } }
      expect(authenticated?).to be true
    end

    it 'signs in when the form submits a MIXED-CASE + WHITESPACE email (the deterministic+downcase contract)' do
      # Stored downcased; the controller only .strip()s the input. AR downcase:true is what makes this
      # equality lookup match — this example FAILS if downcase:true is ever dropped from the encrypts.
      create(:user, email: 'mixed.case@example.org', password: password,
                    password_confirmation: password)
      post user_session_path, params: { user: { email: '  Mixed.Case@EXAMPLE.org  ', password: password } }
      expect(authenticated?).to be true
    end

    it 'rejects a wrong password for an existing encrypted-email account' do
      create(:user, email: 'wrong.pw@example.org', password: password,
                    password_confirmation: password)
      post user_session_path, params: { user: { email: 'wrong.pw@example.org', password: 'NotTheRight1!' } }
      expect(authenticated?).to be false
    end
  end

  describe 'find_for_database_authentication (the exact controller lookup) on encrypted email' do
    it 'matches a record from a mixed-case / whitespace-stripped email' do
      user = create(:user, email: 'lookup.user@example.org')
      # Mirror SessionsController#create: .strip (Devise strip_whitespace_keys), no app-side downcase;
      # AR downcase:true normalizes for the deterministic equality query.
      found = User.find_for_database_authentication(email: '  Lookup.User@Example.ORG  '.strip)
      expect(found).to eq(user)
    end

    it 'returns nil for an email that no user has' do
      create(:user, email: 'present@example.org')
      expect(User.find_for_database_authentication(email: 'absent@example.org')).to be_nil
    end
  end

  describe 'password reset (:recoverable) finds the user by encrypted email' do
    it 'sends reset instructions to a known (case-insensitive) email and sets a reset token' do
      user = create(:user, email: 'reset.me@example.org', password: password,
                           password_confirmation: password)
      expect {
        post user_password_path, params: { user: { email: 'Reset.Me@EXAMPLE.org' } }
      }.to change { user.reload.reset_password_token }.from(nil)
      expect(response).to be_redirect # Devise redirects to sign-in on a successful reset request
    end
  end

  describe 'email uniqueness still rejects a duplicate (case-insensitive) through the model' do
    it 'a second account with the same email (different case) is invalid' do
      create(:user, email: 'unique.staff@example.org', password: password,
                    password_confirmation: password)
      dup = build(:user, email: 'Unique.Staff@EXAMPLE.org', password: password,
                         password_confirmation: password)
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to be_present
    end
  end
end