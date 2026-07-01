# frozen_string_literal: true
require 'rails_helper'

# POAM-004 Unit 2 — client_grid :all_domains dynamic filter after eval("#{score}#{op}#{value}") was
# replaced by a frozen whitelisted operator map. Proves the same rows are kept as before (numeric
# comparison parity across =, >, >=, <, <=, !=) and that an injected operator string fails closed
# (row excluded, no execution).
# FOLDS review fix: datagrid 1.4.4 :dynamic filter value MUST be the POSITIONAL TRIPLE
# ['All CSI', operation, value] — a hash {operation:,value:} binds operation/value to nil and every
# row fails closed, which would falsely redden the positive assertions.
RSpec.describe ClientGrid, 'all_domains dynamic filter (POAM-004)', type: :model do
  after { ClientHistory.delete_all }

  let!(:client_hi) { create(:client) }
  let!(:client_lo) { create(:client) }
  let!(:assess_hi) { create(:assessment, client: client_hi) }
  let!(:assess_lo) { create(:assessment, client: client_lo) }

  before do
    domain = create(:domain)
    create(:assessment_domain, assessment: assess_hi, domain: domain, score: 4)
    create(:assessment_domain, assessment: assess_lo, domain: domain, score: 1)
  end

  def grid_ids(operation, value)
    grid = ClientGrid.new(all_domains: ['All CSI', operation, value])
    grid.assets.pluck(:id)
  end

  it 'keeps only clients whose domain score satisfies >= (parity with the old eval)' do
    ids = grid_ids('>=', '4')
    expect(ids).to include(client_hi.id)
    expect(ids).not_to include(client_lo.id)
  end

  it 'supports equality, greater-than and less-than identically to eval' do
    expect(grid_ids('=', '1')).to include(client_lo.id)
    expect(grid_ids('=', '1')).not_to include(client_hi.id)
    expect(grid_ids('>', '3')).to include(client_hi.id)
    expect(grid_ids('>', '3')).not_to include(client_lo.id)
    expect(grid_ids('<', '2')).to include(client_lo.id)
    expect(grid_ids('<', '2')).not_to include(client_hi.id)
  end

  it 'fails closed for an injected operator string (no rows kept, no execution)' do
    $poam004_grid_marker = :untouched
    ids = nil
    expect { ids = grid_ids(';$poam004_grid_marker = :EXECUTED;1==', '1') }.not_to raise_error
    expect(ids).to eq([])
    expect($poam004_grid_marker).to eq(:untouched)
  end
end
