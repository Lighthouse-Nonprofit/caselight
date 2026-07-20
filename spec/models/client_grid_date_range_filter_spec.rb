# frozen_string_literal: true
require 'rails_helper'

# ClientGrid single-bound date-range filters (deps program: datagrid 1.4.4 -> 2.0.9).
#
# Each `range: true` filter (accepted_date / exit_date / placement_date /
# program_enrollment_date) is a custom block that branches on which bound is present and calls
# `values.first` / `values.second`. Two branches carry pre-existing bugs:
#   * accepted_date upper-bound-only runs `where('DATE(accepted_date) =< ?', values.first)` —
#     `=<` is not a Postgres operator, and it reads `values.first` (the blank/lower bound)
#     instead of the supplied upper bound.
#   * exit_date upper-bound-only reads `values.first` instead of `values.second`, so it filters
#     on the (blank) lower bound and returns nothing.
# On top of that, datagrid 2.0.9 now hands the block a Range ([from, to] "arrival") rather than
# the 1.4.4 positional Array, which is the regression surface these examples pin down.
#
# These assert the INTENDED behavior of an ordinary one-sided / two-sided date range: the right
# clients come back and nothing 500s. No date-range branch had model coverage before this.
RSpec.describe ClientGrid, 'single/double-bound date-range filters', type: :model do
  after { ClientHistory.delete_all }

  # Grid values arrive as [from, to]; a blank slot means that bound is unset.
  def filtered_ids(**filter)
    ClientGrid.new(**filter).assets.pluck(:id)
  end

  it 'accepted_date with only the upper bound returns clients accepted on/before it, without erroring' do
    before_bound = create(:client, accepted_date: Date.new(2020, 3, 1))
    on_bound     = create(:client, accepted_date: Date.new(2020, 6, 30))
    after_bound  = create(:client, accepted_date: Date.new(2021, 3, 1))

    ids = nil
    expect { ids = filtered_ids(accepted_date: ['', '2020-06-30']) }.not_to raise_error
    expect(ids).to include(before_bound.id, on_bound.id) # inclusive of the boundary date
    expect(ids).not_to include(after_bound.id)
  end

  it 'exit_date with only the upper bound filters on the supplied value (not an empty set)' do
    before_bound = create(:client, exit_date: Date.new(2020, 3, 1))
    after_bound  = create(:client, exit_date: Date.new(2021, 3, 1))

    ids = nil
    expect { ids = filtered_ids(exit_date: ['', '2020-06-30']) }.not_to raise_error
    expect(ids).to include(before_bound.id)
    expect(ids).not_to include(after_bound.id)
  end

  it 'placement_date with both bounds keeps clients whose case start_date is in the inclusive range' do
    in_range = create(:client)
    create(:case, client: in_range, start_date: Date.new(2020, 3, 1))
    out_of_range = create(:client)
    create(:case, client: out_of_range, start_date: Date.new(2021, 3, 1))

    ids = filtered_ids(placement_date: ['2020-01-01', '2020-12-31'])
    expect(ids).to include(in_range.id)
    expect(ids).not_to include(out_of_range.id)
  end

  it 'program_enrollment_date lower-bound-only returns only Active enrollments on/after the date' do
    active_after = create(:client)
    create(:client_enrollment, client: active_after, status: 'Active', enrollment_date: Date.new(2020, 3, 1))
    active_before = create(:client)
    create(:client_enrollment, client: active_before, status: 'Active', enrollment_date: Date.new(2019, 3, 1))
    inactive_after = create(:client)
    create(:client_enrollment, client: inactive_after, status: 'Exited', enrollment_date: Date.new(2020, 3, 1))

    ids = filtered_ids(program_enrollment_date: ['2020-01-01', ''])
    expect(ids).to include(active_after.id)
    expect(ids).not_to include(active_before.id)  # Active but before the lower bound
    expect(ids).not_to include(inactive_after.id) # after the bound but not Active
  end
end
