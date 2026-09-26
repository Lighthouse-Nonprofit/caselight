# frozen_string_literal: true
require 'rails_helper'

# 2026-09-26 code pass: UserReminder#remind_manager_and_admin iterated case workers grouped by
# manager and used `return` (not `next`) when a group's top manager had already been handled. The
# first repeated top manager therefore ended the WHOLE method: every later manager chain, and the
# no-manager branch, went unreminded for that organisation.
RSpec.describe UserReminder do
  let(:org) { Organization.first }

  # Two chains. Chain A: top manager A -> mid manager B -> case worker cw1, plus cw4 directly under A.
  # Chain C: top manager C -> case worker cw2. Created in this order so an id-ordered query groups
  # them B, A, C -- which is exactly the sequence that tripped the `return`.
  let!(:top_a) { create(:user, :manager) }
  let!(:mid_b) { create(:user, :manager, manager_id: top_a.id) }
  let!(:top_c) { create(:user, :manager) }
  let!(:cw1)   { create(:user, manager_id: mid_b.id) }
  let!(:cw4)   { create(:user, manager_id: top_a.id) }
  let!(:cw2)   { create(:user, manager_id: top_c.id) }

  before do
    [cw1, cw4, cw2].each do |cw|
      create(:task, :incomplete, completion_date: 3.days.ago.to_date).tap { |t| t.users = [cw] }
    end
    # group_by follows query order; pin it so the spec is deterministic.
    allow(User).to receive(:without_json_fields).and_wrap_original { |m| m.call.order(:id) }
    allow(ManagerWorker).to receive(:perform_async)
    allow(CaseManagerWorker).to receive(:perform_async)
    allow(AdminWorker).to receive(:perform_async)
  end

  it 'reminds every manager chain, not just up to the first repeated top manager' do
    described_class.new.send(:remind_manager_and_admin, org)

    # Chain A is handled through mid_b's group (mid_b, cw1, cw4 and top_a get a reminder); the
    # original `return` then fired on top_a's own group and chain C never ran.
    expect(ManagerWorker).to have_received(:perform_async).with(mid_b.id, anything, org.short_name)
    expect(ManagerWorker).to have_received(:perform_async).with(top_c.id, anything, org.short_name)
    expect(ManagerWorker).to have_received(:perform_async).with(cw2.id, anything, org.short_name)
  end
end
