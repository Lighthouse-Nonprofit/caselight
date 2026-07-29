# frozen_string_literal: true
require 'rails_helper'

# POAM-025 — ClientBaseSqlBuilder#name_encrypted_sql resolves is_empty / is_not_empty on the Tier-4
# deterministically-encrypted name columns in SQL (probe `[nil, '']`) instead of the retired
# decrypt-every-client Ruby scan. Parity oracle = the retired scan's semantics (per-client
# `present?`), computed up front from decrypted records; the generated fragment is then applied
# through the exact consumer idiom (ClientAdvancedSearch#filter: `clients.where([sql, *values])`)
# and must select the same ids WITHOUT touching a decrypted name reader.
#
# Accepted divergence (documented in the builder): whitespace-only names count as NOT empty under
# the SQL probe. Not exercised here — names are never stored as bare whitespace.
RSpec.describe 'ClientBaseSqlBuilder Tier-4 empty-operator SQL (POAM-025)', type: :model do
  after { ClientHistory.delete_all }

  def search(field, operator, value = '')
    rules = { 'condition' => 'AND',
              'rules' => [{ 'id' => field, 'field' => field, 'type' => 'string', 'input' => 'text',
                            'operator' => operator, 'value' => value }] }
    result = AdvancedSearches::ClientBaseSqlBuilder.new(Client.all, rules).generate
    Client.where([result[:sql_string], *result[:values]])
  end

  let!(:named)   { create(:client, given_name: 'Maria', family_name: 'Gonzalez') }
  let!(:blank)   { create(:client, given_name: '',      family_name: 'BlankGiven') }
  let!(:unnamed) { create(:client, given_name: nil,     family_name: 'NilGiven') }

  it 'is_empty matches the legacy decrypted-present? oracle without decrypting any client' do
    oracle = Client.all.reject { |c| c.given_name.present? }.map(&:id).sort
    expect(oracle).to match_array([blank.id, unnamed.id].sort) # fixture sanity

    expect_any_instance_of(Client).not_to receive(:given_name)
    expect(search('given_name', 'is_empty').ids.sort).to eq(oracle)
  end

  it 'is_not_empty matches the legacy oracle complement without decrypting any client' do
    oracle = Client.all.select { |c| c.given_name.present? }.map(&:id).sort
    expect(oracle).to eq([named.id]) # fixture sanity

    expect_any_instance_of(Client).not_to receive(:given_name)
    expect(search('given_name', 'is_not_empty').ids.sort).to eq(oracle)
  end

  it 'equal still resolves through the deterministic scope, case-insensitively (regression)' do
    expect(search('given_name', 'equal', 'maria').ids).to eq([named.id])
  end

  it 'not_equal keeps missing-value semantics: blank and nil names are NOT equal to the probe' do
    expect(search('given_name', 'not_equal', 'Maria').ids.sort).to eq([blank.id, unnamed.id].sort)
  end
end
