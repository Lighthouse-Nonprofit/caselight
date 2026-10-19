# frozen_string_literal: true
require 'rails_helper'

# 2026-10-18 security pass: the advanced-search `condition` came straight from the request's JSON and
# was joined into the WHERE clause verbatim. It can only ever be AND or OR now.
RSpec.describe 'ClientBaseSqlBuilder condition joiner', type: :model do
  after { ClientHistory.delete_all rescue nil }

  def rules_with(condition)
    { 'condition' => condition,
      'rules' => [
        { 'id' => 'given_name', 'field' => 'given_name', 'type' => 'string', 'input' => 'text', 'operator' => 'is_empty', 'value' => '' },
        { 'id' => 'family_name', 'field' => 'family_name', 'type' => 'string', 'input' => 'text', 'operator' => 'is_empty', 'value' => '' }
      ] }
  end

  it 'joins with OR when asked' do
    sql = AdvancedSearches::ClientBaseSqlBuilder.new(Client.all, rules_with('OR')).generate[:sql_string]
    expect(sql).to include(' OR ')
    expect(sql).not_to include(' AND ')
  end

  it 'falls back to AND for anything that is not OR, including injected SQL' do
    sql = AdvancedSearches::ClientBaseSqlBuilder.new(Client.all, rules_with("OR 1=1 --")).generate[:sql_string]
    expect(sql).to include(' AND ')
    expect(sql).not_to include('1=1')
  end

  it 'skips a rule that names a program that no longer exists instead of raising' do
    rules = { 'condition' => 'AND',
              'rules' => [{ 'id' => 'enrollment_Gone Program_x', 'field' => 'enrollment_Gone Program_x', 'type' => 'string',
                            'input' => 'text', 'operator' => 'equal', 'value' => 'y' }] }
    expect { AdvancedSearches::ClientBaseSqlBuilder.new(Client.all, rules).generate }.not_to raise_error
  end
end
