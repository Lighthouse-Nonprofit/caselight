# frozen_string_literal: true
require 'rails_helper'

# 2026-10-18 security pass: CaseNote#complete_tasks took task ids straight from the form and did
# Task.where(id:), so a case note on client A could re-parent and complete client B's tasks.
RSpec.describe 'CaseNote#complete_tasks scoping', type: :model do
  after { ClientHistory.delete_all rescue nil }

  let!(:client_a)  { create(:client) }
  let!(:client_b)  { create(:client) }
  let!(:group)     { create(:domain_group) }
  let!(:case_note) { create(:case_note, client: client_a) }
  let!(:own_task)  { create(:task, :incomplete, client: client_a) }
  let!(:foreign)   { create(:task, :incomplete, client: client_b) }

  it 'completes the client\'s own task and ignores another client\'s task id' do
    section = case_note.case_note_domain_groups.create!(domain_group: group)
    case_note.complete_tasks({ '0' => { domain_group_id: group.id, task_ids: [own_task.id, foreign.id] } })

    expect(own_task.reload.completed).to be(true)
    expect(foreign.reload.completed).to be(false)
    expect(section.tasks.reload).to eq([own_task])
    expect(foreign.reload.case_note_domain_group_id).not_to eq(section.id)
  end
end
