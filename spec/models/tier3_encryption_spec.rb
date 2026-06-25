# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 3 — field-level encryption-at-rest regression specs for STAFF-ACCOUNT PII
# (FedRAMP SC-28, SOC 2 C1.1). Tier 3 is DETERMINISTIC (unlike Tiers 1-2): same plaintext => same
# ciphertext, so EQUALITY queries + the users.email unique index survive; iLIKE substring / range /
# ORDER BY do not. This file proves: the five User columns (email, first_name, last_name, mobile, uid)
# are `encrypts`-declared + round-trip (transparent decrypt on read; ciphertext envelope in the raw DB
# column); email + uid are deterministic + downcase:true; the unique index/validation still reject a
# case-insensitive duplicate email; uid no longer leaks plaintext email; the rewritten exact-match
# *_like scopes work; UserGrid is exact-match with name/email ORDER BY dropped; and the Client
# is_received_by / is_followed_up_by option scopes build decrypted names in Ruby AND still scope to the
# caller's relation (the authorization-regression guard). The MANDATORY login-path specs (sign-in,
# reset, find_for_database_authentication normalization) live in spec/requests/tier3_user_email_auth_spec.rb.
#
# Runs in tenant 'app' (spec_helper before(:each) switches there). Client saves write a ClientHistory
# doc to Mongo (after_save :create_client_history); DatabaseCleaner is active_record-only, so we clean
# ClientHistory ourselves around Client-creating examples. Mirrors spec/models/tier2_encryption_spec.rb.
RSpec.describe 'Tier 3 staff-account PII encryption at rest (SC-28, deterministic)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's transparent decrypt)
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  USER_TIER3_COLUMNS = %i[email first_name last_name mobile uid].freeze

  describe 'declared encrypted attributes' do
    it 'encrypts the five Tier 3 User columns' do
      expect(User.encrypted_attributes).to include(*USER_TIER3_COLUMNS)
    end

    it 'widened the five columns to text so the deterministic ciphertext envelope fits' do
      USER_TIER3_COLUMNS.each do |col|
        expect(User.columns_hash[col.to_s].type).to eq(:text), "expected users.#{col} to be :text"
      end
    end

    # Behavioral assertion of deterministic+downcase for email (avoids brittle private scheme API):
    # two saves of the same plaintext => identical raw ciphertext, and a mixed-case query matches.
    it 'email is DETERMINISTIC (stable ciphertext) and case-insensitive (downcase)' do
      u = create(:user, email: 'Determinism.Check@example.org')
      raw1 = raw_column(User, u.id, :email)
      u.update!(first_name: 'Touched')
      expect(raw_column(User, u.id, :email)).to eq(raw1) # deterministic: stable ciphertext
      expect(User.find_by(email: 'DETERMINISM.CHECK@example.org')).to eq(u) # downcase: mixed-case matches
    end
  end

  describe 'round-trip + raw-ciphertext (User)' do
    it 'decrypts transparently on read but stores ciphertext in every raw column' do
      user = create(:user, email: 'Casework.Staff@example.org',
                           first_name: 'Maria', last_name: 'Gonzalez', mobile: '+15551234567')
      user.update!(uid: user.email) # exercise the legacy uid==email invariant

      reloaded = User.find(user.id)
      expect(reloaded.email).to eq('casework.staff@example.org') # downcased on write
      expect(reloaded.uid).to eq('casework.staff@example.org')
      expect(reloaded.first_name).to eq('Maria')
      expect(reloaded.last_name).to eq('Gonzalez')
      expect(reloaded.mobile).to eq('+15551234567')

      USER_TIER3_COLUMNS.each do |col|
        raw = raw_column(User, user.id, col)
        expect(raw).to be_present, "expected users.#{col} to be stored"
        expect(raw).not_to eq(reloaded.public_send(col)), "expected raw users.#{col} to be ciphertext"
      end
    end
  end

  describe 'uid (vestigial devise_token_auth plaintext-email copy) no longer leaks' do
    it 'encrypts uid and keeps it byte-identical to the email ciphertext when set to the email' do
      user = create(:user, email: 'Casey.Doe@example.org')
      user.update!(uid: user.email)
      raw_uid = raw_column(User, user.id, :uid)
      expect(raw_uid).to be_present
      expect(raw_uid).not_to include('casey.doe@example.org') # no plaintext email in the raw column
      expect(raw_uid).to eq(raw_column(User, user.id, :email)) # same deterministic+downcase scheme
    end
  end

  describe 'deterministic email uniqueness (model validation + DB unique index)' do
    it 'rejects a duplicate email case-insensitively via the model validation' do
      create(:user, email: 'dup@example.org')
      dup = build(:user, email: 'DUP@Example.org')
      expect(dup).not_to be_valid
      expect(dup.errors[:email]).to be_present
    end

    it 'the DB unique index also rejects a duplicate when validations are skipped' do
      create(:user, email: 'dbdup@example.org')
      expect {
        User.new(email: 'dbdup@example.org', password: 'SecurePass123!',
                 password_confirmation: 'SecurePass123!', roles: 'case worker',
                 program_warning: true).save!(validate: false)
      }.to raise_error(ActiveRecord::RecordNotUnique)
    end
  end

  describe 'rewritten exact-match scopes (deterministic equality replaces iLIKE substring)' do
    it 'first_name_like / last_name_like / mobile_like / email_like match by exact equality' do
      match  = create(:user, first_name: 'Aabid', last_name: 'Nguyen', mobile: '+15550001111',
                             email: 'aabid.nguyen@example.org')
      other  = create(:user, first_name: 'Bborah', last_name: 'Smith', mobile: '+15559998888',
                             email: 'bborah.smith@example.org')

      expect(User.first_name_like('Aabid')).to include(match)
      expect(User.first_name_like('Aabid')).not_to include(other)
      expect(User.last_name_like('Nguyen')).to include(match)
      expect(User.mobile_like('+15550001111')).to include(match)
      expect(User.email_like('aabid.nguyen@example.org')).to include(match)
      # email_like is case-insensitive (downcase:true normalizes the query value too)
      expect(User.email_like('Aabid.Nguyen@EXAMPLE.org')).to include(match)
      # substring no longer matches (ciphertext equality is exact)
      expect(User.first_name_like('Aab')).to be_empty
      # first_name_like is NOT downcased — a case-mismatched value does not match
      expect(User.first_name_like('aabid')).not_to include(match)
    end
  end

  describe 'UserGrid (exact-match filters, no ORDER BY on encrypted columns)' do
    it 'filters email/first_name/last_name/mobile by exact match' do
      target = create(:user, first_name: 'Quincy', last_name: 'Adams',
                             email: 'quincy.adams@example.org', mobile: '+15557776666')
      create(:user, first_name: 'Other', last_name: 'Person')

      expect(UserGrid.new(first_name: 'Quincy').assets).to include(target)
      expect(UserGrid.new(email: 'quincy.adams@example.org').assets).to include(target)
      expect(UserGrid.new(mobile: '+15557776666').assets).to include(target)
      expect(UserGrid.new(first_name: 'Quin').assets).not_to include(target) # substring no longer matches
    end

    it 'no longer ORDER BYs the encrypted name column but keeps it + the PII columns as display columns' do
      name_col = UserGrid.columns.find { |c| c.name == :name }
      expect(name_col).to be_present
      expect(name_col.order).to be_falsey # LOWER(users.first_name), LOWER(users.last_name) removed
      %i[email first_name last_name mobile].each do |c|
        expect(UserGrid.columns.find { |x| x.name == c }).to be_present, "expected column #{c} kept"
      end
    end

    it 'keeps the non-PII filters intact (pin_number NOT encrypted)' do
      filter_names = UserGrid.filters.map(&:name)
      expect(filter_names).to include(:job_title, :department, :roles, :province_id, :pin_number,
                                      :date_of_birth, :start_date, :id)
    end
  end

  describe 'Client option scopes: decrypted names AND preserved per-user scoping' do
    after { ClientHistory.delete_all }

    it 'is_received_by builds [decrypted-name, id] in Ruby (not a SQL CONCAT of ciphertext)' do
      worker = create(:user, first_name: 'Reci', last_name: 'Pient')
      create(:client, received_by: worker, user_ids: [worker.id])
      opts = Client.is_received_by
      expect(opts).to be_an(Array)
      expect(opts).to include(['Reci Pient', worker.id])
      # not a base64 ciphertext concatenation
      opts.each { |name, _id| expect(name).not_to match(%r{\A[A-Za-z0-9+/]{40,}}) }
    end

    it 'is_followed_up_by builds [decrypted-name, id] in Ruby' do
      worker = create(:user, first_name: 'Foll', last_name: 'Ower')
      create(:client, followed_up_by: worker, user_ids: [worker.id])
      expect(Client.is_followed_up_by).to include(['Foll Ower', worker.id])
    end

    # AUTHORIZATION GUARD: the callers chain a per-user where BEFORE calling these scopes
    # (e.g. Client.where(user_id: x).is_received_by in advanced_searches/client_fields.rb and
    # client_grid.rb). As `scope`s the joins() merges with that where, so a worker only sees their own
    # clients' receivers. A def self. rewrite would DROP that scoping and leak the full staff list.
    it 'is_received_by, when chained on a scoped relation, only returns that relation\'s receivers' do
      worker_a = create(:user, first_name: 'Alpha', last_name: 'Worker')
      worker_b = create(:user, first_name: 'Beta',  last_name: 'Worker')
      client_a = create(:client, received_by: worker_a, user_ids: [worker_a.id])
      create(:client, received_by: worker_b, user_ids: [worker_b.id])

      scoped = Client.where(id: client_a.id).is_received_by
      expect(scoped).to include(['Alpha Worker', worker_a.id])
      expect(scoped).not_to include(['Beta Worker', worker_b.id])
    end
  end

  describe 'out-of-scope columns are untouched' do
    it 'does NOT encrypt pin_number (integer; hash-vs-deterministic decision pending with the org)' do
      expect(User.encrypted_attributes).not_to include(:pin_number)
      expect(User.columns_hash['pin_number'].type).to eq(:integer)
    end
  end
end