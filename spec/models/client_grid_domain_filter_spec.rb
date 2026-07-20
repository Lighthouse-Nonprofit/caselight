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

# ---------------------------------------------------------------------------------------------------
# Per-domain dynamic filters :domain_1a .. :domain_6b  (ClientGrid.client_by_domain)
#
# Each of the 12 per-domain filters scores clients within ONE CSI Domain. Its datagrid 2.0 :dynamic
# block receives a FilterValue and delegates:
#
#     client_by_domain(filter.operation, filter.value.to_i, filter.field, scope)
#         ids = Assessment.joins(:assessment_domains)
#                         .where("score#{operation} ? AND domain_id= ?", value, domain_id).ids
#         scope.joins(:assessments).where(assessments: { id: ids })
#
# Notes that shape these examples (all confirmed against the code / datagrid 2.0.9 internals):
#   * filter.field == the Domain#id supplied by the `select: proc { get_domain('1A') }` option, i.e.
#     [[domain.name, domain.id]]. Real params arrive as strings, and datagrid's FilterValue parser
#     (DynamicFilter::FilterValue#initialize -> driver.normalized_column_type) RAISES NameError on a
#     non-string field, so `field` is passed here as a string (domain.id.to_s), matching production.
#   * datagrid's custom-block path bypasses DynamicFilter#default_filter_where, so datagrid's own
#     operation whitelist (AVAILABLE_OPERATIONS) never runs — whatever `operation` arrives is handed
#     straight to client_by_domain and string-interpolated into the WHERE. all_domains was remediated
#     with a frozen operator map (DOMAIN_SCORE_OPS); the 12 domain_X paths were NOT — these examples
#     assert the INTENDED (secure, all_domains-parity) contract:
#       - a per-domain filter is scoped strictly to its own Domain (no cross-domain leakage),
#       - an injected operator fails closed (no tautology, no leaked rows) like all_domains,
#       - the =~ operator the :dynamic dropdown exposes must not reach Postgres verbatim and 500.
RSpec.describe ClientGrid, 'per-domain dynamic filters domain_1a..domain_6b (client_by_domain)', type: :model do
  after { ClientHistory.delete_all }

  let!(:domain_1a) { create(:domain, name: '1A') }
  let!(:domain_2a) { create(:domain, name: '2A') }

  let!(:client_hi)    { create(:client) }
  let!(:client_lo)    { create(:client) }
  let!(:client_other) { create(:client) }

  let!(:assess_hi)    { create(:assessment, client: client_hi) }
  let!(:assess_lo)    { create(:assessment, client: client_lo) }
  let!(:assess_other) { create(:assessment, client: client_other) }

  before do
    # client_hi: high 1A score; client_lo: low 1A score; client_other: high score but a DIFFERENT domain
    create(:assessment_domain, assessment: assess_hi,    domain: domain_1a, score: 4)
    create(:assessment_domain, assessment: assess_lo,    domain: domain_1a, score: 1)
    create(:assessment_domain, assessment: assess_other, domain: domain_2a, score: 4)
  end

  # field defaults to the 1A domain id (as a string, as production params arrive).
  def domain_1a_ids(operation, value, field: domain_1a.id.to_s)
    ClientGrid.new(domain_1a: { field: field, operation: operation, value: value }).assets.pluck(:id)
  end

  it 'keeps only clients whose 1A score satisfies the comparison and stays scoped to domain 1A' do
    ids = domain_1a_ids('>=', '3')

    expect(ids).to include(client_hi.id)          # score 4 in 1A satisfies >= 3
    expect(ids).not_to include(client_lo.id)      # score 1 in 1A fails >= 3
    expect(ids).not_to include(client_other.id)   # score 4 but in domain 2A -> outside a 1A filter
  end

  it 'does not interpolate an injected operation into SQL (fails closed like all_domains)' do
    ids = nil
    # If interpolated verbatim, "score=0 OR 1=1 -- " turns the WHERE into a tautology and the trailing
    # "?  AND domain_id= ?" is commented out, leaking every client. The intended (POAM-004-sibling)
    # behavior is an unknown operator matching nothing.
    expect { ids = domain_1a_ids('=0 OR 1=1 -- ', '1') }.not_to raise_error
    expect(ids).not_to include(client_lo.id)
    expect(ids).not_to include(client_other.id)
    expect(ids).to eq([])
  end

  it 'does not raise a PostgreSQL error for the =~ operation the :dynamic dropdown offers' do
    # '=~' is one of datagrid's DEFAULT_OPERATIONS (so the dropdown exposes it), but `score` is an
    # integer column: "score=~ ?" reaching Postgres verbatim is PG::UndefinedFunction, i.e. a 500 on
    # a legitimate dropdown selection. A numeric domain filter must degrade gracefully instead.
    expect { domain_1a_ids('=~', '3') }.not_to raise_error
  end

  it 'get_domain returns the [name, id] option when the Domain exists and [] when it does not' do
    expect(ClientGrid.get_domain('1A')).to eq([['1A', domain_1a.id]])
    # No Domain named '3B' exists -> empty select options, so the domain_3b filter is a no-op.
    expect(ClientGrid.get_domain('3B')).to eq([])
  end
end
