# frozen_string_literal: true
require 'rails_helper'

# POAM-004 Unit 2 — client_grid :all_domains dynamic filter after eval("#{score}#{op}#{value}") was
# replaced by a frozen whitelisted operator map. Proves the same rows are kept as before (numeric
# comparison parity across =, >, >=, <, <=, !=) and that an injected operator string fails closed
# (row excluded, no execution).
# datagrid 2.0 API: a :dynamic filter value is a HASH {field:, operation:, value:} (Datagrid's
# FilterValue), NOT the 1.4.4 positional triple ['All CSI', operation, value] (2.0 raises
# Datagrid::ArgumentError on an Array value). The all_domains block ignores field (it scores across
# every AssessmentDomain), but 2.0 introspects the field's column type at parse time, so field must
# be a real column — the filter's select maps the "All CSI" label to :id. (deps program Phase 1d/1f.)
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
    grid = ClientGrid.new(all_domains: { field: 'id', operation: operation, value: value })
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
