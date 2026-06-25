# frozen_string_literal: true
require 'rails_helper'

# Phase 4 Tier 4 — field-level encryption-at-rest regression specs for CLIENT NAME PII
# (FedRAMP SC-28, SOC 2 C1.1). Tier 4 is DETERMINISTIC encryption (same plaintext => same ciphertext),
# mirroring the Tier 3 staff-name approach: EXACT equality lookup (where(given_name: 'Maria')) still
# works; iLIKE substring + ORDER BY over ciphertext do NOT.
#
# NO downcase => the match is exact and CASE-SENSITIVE ('MARIA' does not match 'Maria'), but the stored
# (and therefore displayed) value keeps its original casing. Substring name search (the old iLIKE
# '%value%') downgrades to whole-name exact match — the documented trade-off the locked decision accepted
# when prefix lookup proved impossible over an HMAC and blind_index was declined.
#
# Runs in tenant 'app' (spec_helper switches there). Client saves write a ClientHistory doc to Mongo via
# after_save :create_client_history; DatabaseCleaner is active_record-only, so we clean ClientHistory
# ourselves around Client-creating examples. Mirrors spec/models/tier2_encryption_spec.rb /
# tier3_encryption_spec.rb. `create(:client, ...)` is a normal save (the factory adds a user, satisfying
# validates :user_ids), so the encrypted columns are written via the encrypted type automatically — the
# specs do NOT depend on the rake backfill (that path is the backfill's own concern).
RSpec.describe 'Tier 4 client-name deterministic encryption at rest (SC-28)', type: :model do
  # raw, un-decrypted column value straight from Postgres (bypasses the model's transparent decrypt)
  def raw_column(model, id, col)
    conn = model.connection
    conn.select_value(
      "SELECT #{conn.quote_column_name(col)} FROM #{conn.quote_table_name(model.table_name)} " \
      "WHERE #{conn.quote_column_name(model.primary_key)} = #{conn.quote(id)}"
    )
  end

  CLIENT_TIER4_COLUMNS = %i[given_name family_name local_given_name local_family_name].freeze

  describe 'declared encrypted attributes' do
    it 'encrypts the four Client name columns' do
      expect(Client.encrypted_attributes).to include(*CLIENT_TIER4_COLUMNS)
    end

    it 'widened the four name columns to text so the ciphertext envelope fits' do
      CLIENT_TIER4_COLUMNS.each do |col|
        expect(Client.columns_hash[col.to_s].type).to eq(:text), "expected clients.#{col} to be :text"
      end
    end
  end

  describe 'round-trip + raw ciphertext + deterministic property' do
    after { ClientHistory.delete_all }

    it 'decrypts names transparently on read but stores a ciphertext envelope in the raw columns' do
      values = {
        given_name:        'Maria',
        family_name:       'Gonzalez',
        local_given_name:  'Mariam',
        local_family_name: 'Gonzales'
      }
      client = create(:client, values)

      reloaded = Client.find(client.id)
      values.each do |col, plaintext|
        expect(reloaded.public_send(col)).to eq(plaintext), "expected #{col} to decrypt to #{plaintext.inspect}"
        raw = raw_column(Client, client.id, col)
        expect(raw).to be_present
        expect(raw).not_to eq(plaintext), "expected raw clients.#{col} to be ciphertext, not plaintext"
      end
    end

    it 'is DETERMINISTIC — the same plaintext name encrypts to the same ciphertext (enabling equality lookup)' do
      a = create(:client, given_name: 'Maria')
      b = create(:client, given_name: 'Maria')
      c = create(:client, given_name: 'Different')

      raw_a = raw_column(Client, a.id, :given_name)
      raw_b = raw_column(Client, b.id, :given_name)
      raw_c = raw_column(Client, c.id, :given_name)
      expect(raw_a).to eq(raw_b), 'expected identical plaintext to produce identical deterministic ciphertext'
      expect(raw_a).not_to eq(raw_c)
    end
  end

  describe 'equality lookup (exact, case-sensitive)' do
    after { ClientHistory.delete_all }

    it 'finds a client by exact name and NOT by a case-variant (deterministic, no downcase) or a substring' do
      match = create(:client, given_name: 'Maria', family_name: 'Gonzalez',
                              local_given_name: 'Mariam', local_family_name: 'Gonzales')
      other = create(:client, given_name: 'Bao',   family_name: 'Tran')

      expect(Client.where(given_name: 'Maria')).to include(match)
      expect(Client.where(given_name: 'Maria')).not_to include(other)
      expect(Client.where(family_name: 'Gonzalez')).to include(match)
      expect(Client.where(local_given_name: 'Mariam')).to include(match)
      expect(Client.where(local_family_name: 'Gonzales')).to include(match)

      # CASE-SENSITIVE: a differently-cased query does not match (no downcase normalization).
      expect(Client.where(given_name: 'MARIA')).not_to include(match)
      expect(Client.where(family_name: 'gonzalez')).not_to include(match)
      # No substring: a prefix of the name does not match (exact equality only).
      expect(Client.where(given_name: 'Mar')).to be_empty
    end
  end

  describe 'rewritten *_like scopes (deterministic equality replaces iLIKE substring)' do
    after { ClientHistory.delete_all }

    it 'given/family/local_given/local_family _like match by exact (case-sensitive) equality, not substring' do
      match = create(:client, given_name: 'Maria', family_name: 'Gonzalez',
                              local_given_name: 'Mariam', local_family_name: 'Gonzales')
      create(:client, given_name: 'Bao', family_name: 'Tran')

      expect(Client.given_name_like('Maria')).to include(match)
      expect(Client.family_name_like('Gonzalez')).to include(match)
      expect(Client.local_given_name_like('Mariam')).to include(match)
      expect(Client.local_family_name_like('Gonzales')).to include(match)
      expect(Client.given_name_like('MARIA')).to be_empty   # case-sensitive
      expect(Client.given_name_like('Mar')).to be_empty      # no substring
    end
  end

  describe 'Client.filter (deterministic equality on names; DOB stays plaintext EXTRACT)' do
    after { ClientHistory.delete_all }

    it 'filters by exact name and no longer builds an iLIKE on the name columns' do
      match = create(:client, given_name: 'Maria', family_name: 'Gonzalez')
      create(:client, given_name: 'Bao', family_name: 'Tran')

      result = Client.filter(given_name: 'Maria', family_name: 'Gonzalez')
      expect(result).to include(match)

      sql = Client.filter(given_name: 'Maria').to_sql.downcase
      expect(sql).to include('given_name')          # the column is referenced
      expect(sql).not_to include('given_name ilike') # but NOT via substring iLIKE
    end

    it 'keeps the date_of_birth EXTRACT(MONTH/YEAR) clause (DOB is plaintext)' do
      sql = Client.filter(date_of_birth: '2015-04-09').to_sql.downcase
      expect(sql).to include('extract(month from date_of_birth)')
      expect(sql).to include('extract(year from date_of_birth)')
    end
  end

  describe 'display methods operate on decrypted attributes (unchanged, original casing preserved)' do
    after { ClientHistory.delete_all }

    it 'Client#name and #en_and_local_name concat the decrypted names with original casing' do
      c = create(:client, given_name: 'Maria', family_name: 'Gonzalez',
                          local_given_name: 'Mariam', local_family_name: 'Gonzales')
      expect(c.name).to eq('Maria Gonzalez')
      expect(c.en_and_local_name).to eq('Maria Gonzalez (Mariam Gonzales)')
    end
  end

  # ---------------------------------------------------------------------------------------------
  # QUERY SURFACE — advanced-search field lists, FilterTypes, ClientBaseSqlBuilder, ClientGrid,
  # families_controller.
  # ---------------------------------------------------------------------------------------------

  describe 'advanced-search field lists (deterministic equality, no substring)' do
    it 'rule_fields drops the four name columns from the substring text list' do
      text_fields = AdvancedSearches::RuleFields.new.send(:text_type_list)
      %w[given_name family_name local_given_name local_family_name].each do |f|
        expect(text_fields).not_to include(f), "expected rule_fields text_type_list to drop #{f}"
      end
      expect(text_fields).to include('family', 'slug', 'referral_phone')
    end

    it 'rule_fields exposes the four name columns as encrypted (equality-only) fields' do
      enc_fields = AdvancedSearches::RuleFields.new.send(:encrypted_name_type_list)
      expect(enc_fields).to match_array(%w[given_name family_name local_given_name local_family_name])
    end

    it 'client_fields drops given_name/family_name from the substring text list' do
      text_fields = AdvancedSearches::ClientFields.new.send(:text_type_list)
      expect(text_fields).not_to include('given_name')
      expect(text_fields).not_to include('family_name')
      expect(text_fields).to include('family', 'slug')
    end

    it 'client_fields exposes given_name/family_name as encrypted (equality-only) fields' do
      enc_fields = AdvancedSearches::ClientFields.new.send(:encrypted_name_type_list)
      expect(enc_fields).to match_array(%w[given_name family_name])
    end

    it 'text_equal_options omits the substring operators contains / not_contains' do
      opts = AdvancedSearches::FilterTypes.text_equal_options('given_name', 'Given Name', 'Basic')
      expect(opts[:operators]).to match_array(%w[equal not_equal is_empty is_not_empty])
      expect(opts[:operators]).not_to include('contains')
      expect(opts[:operators]).not_to include('not_contains')
      expect(opts[:type]).to eq('string')
    end

    it 'rendered rule_fields offer equality-only operators for the name fields' do
      rendered = AdvancedSearches::RuleFields.new.render
      given = rendered.find { |f| f[:id] == 'given_name' }
      expect(given).to be_present
      expect(given[:operators]).not_to include('contains', 'not_contains')
    end
  end

  describe 'advanced-search SQL builder routes names through the deterministic equality scope' do
    after { ClientHistory.delete_all }

    # Consume the builder via the REAL production consumer (ClientAdvancedSearch#filter): generate
    # returns { values: [ <id_array> ] } against one `IN (?)` placeholder; the consumer binds each
    # @values element once and Rails expands the array for IN (?). Splat-flattening would raise
    # PreparedStatementInvalid, so we assert structure on built[:sql_string] but behaviour via #filter.
    it 'an `equal` rule on given_name resolves to a clients.id IN (?) clause (not raw clients.given_name =)' do
      match = create(:client, given_name: 'Solara', family_name: 'Quint')
      create(:client, given_name: 'Different', family_name: 'Person')

      rules = { 'condition' => 'AND',
                'rules' => [{ 'field' => 'given_name', 'operator' => 'equal', 'value' => 'Solara' }] }
      built = AdvancedSearches::ClientBaseSqlBuilder.new(Client.all, rules).generate
      expect(built[:sql_string]).to include('clients.id IN (?)')
      expect(built[:sql_string].downcase).not_to include('clients.given_name =')
      expect(built[:sql_string].downcase).not_to include('clients.given_name ilike')

      result = AdvancedSearches::ClientAdvancedSearch.new(rules, Client.all).filter
      expect(result).to include(match)
      expect(result.count).to eq(1)
    end

    it 'equality on a name is case-sensitive (deterministic, no downcase) — a mis-cased value matches nothing' do
      create(:client, given_name: 'Solara', family_name: 'Quint')
      rules = { 'condition' => 'AND',
                'rules' => [{ 'field' => 'given_name', 'operator' => 'equal', 'value' => 'SOLARA' }] }
      result = AdvancedSearches::ClientAdvancedSearch.new(rules, Client.all).filter
      expect(result).to be_empty
    end
  end

  describe 'ClientGrid (deterministic-equality filters, no SQL ORDER on ciphertext)' do
    after { ClientHistory.delete_all }

    it 'keeps the given_name / family_name filters' do
      filter_names = ClientGrid.filters.map(&:name)
      expect(filter_names).to include(:given_name, :family_name)
    end

    it 'the given_name filter matches by exact (case-sensitive) equality, not substring' do
      target = create(:client, given_name: 'Solara', family_name: 'Quint')
      create(:client, given_name: 'Other', family_name: 'Name')
      expect(ClientGrid.new(given_name: 'Solara').assets).to include(target)
      expect(ClientGrid.new(given_name: 'solara').assets).not_to include(target) # case-sensitive
      expect(ClientGrid.new(given_name: 'Sol').assets).not_to include(target)    # no substring
    end

    it 'no longer ORDER BYs the encrypted name columns but keeps them as display columns' do
      ClientGrid.columns.select { |c| [:given_name, :family_name].include?(c.name) }.each do |col|
        expect(col.order).to be_falsey, "expected ORDER BY removed from #{col.name} column"
      end
      expect(ClientGrid.columns.map(&:name)).to include(:given_name, :family_name)
    end

    it 'the grid scope ORDER BY no longer references given_name (status-only SQL order)' do
      sql = ClientGrid.new.assets.to_sql.downcase
      expect(sql).to include('order by')
      expect(sql).to include('clients.status')
      expect(sql).not_to include('clients.given_name')
    end

    it 'name_sorted_assets returns clients ordered by status then decrypted name in Ruby' do
      c_b = create(:client, status: 'Referred', given_name: 'Bravo', family_name: 'Z')
      c_a = create(:client, status: 'Referred', given_name: 'Alpha', family_name: 'Z')
      sorted = ClientGrid.new.name_sorted_assets
      expect(sorted.index(c_a)).to be < sorted.index(c_b)
    end
  end

  describe 'families_controller association list not SQL-ordered by name' do
    it 'FamiliesController#find_association builds no ORDER BY on given_name/family_name' do
      src = File.read(Rails.root.join('app', 'controllers', 'families_controller.rb'))
      assoc = src[/def find_association.*?end/m]
      expect(assoc).to be_present
      expect(assoc).not_to match(/\.order\(:given_name/)
      expect(assoc).not_to match(/\.order\(:family_name/)
      expect(assoc).to include('sort_by')
    end
  end
end
