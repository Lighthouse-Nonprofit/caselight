describe CaseNote, 'associations' do
  it { is_expected.to belong_to(:client) }
  it { is_expected.to belong_to(:assessment) }
  it { is_expected.to have_many(:case_note_domain_groups) }
  it { is_expected.to have_many(:domain_groups) }

  it { is_expected.to accept_nested_attributes_for(:case_note_domain_groups) }
end

describe CaseNote, 'validations' do
  it { is_expected.to validate_presence_of(:meeting_date) }
  it { is_expected.to validate_presence_of(:attendee) }
end

describe CaseNote, 'methods' do
  let!(:case_note){ create(:case_note) }
  
  context 'populate notes' do
    let!(:domain_group){ create(:domain_group) }
    before do
      case_note.populate_notes
    end

    it { expect(case_note.case_note_domain_groups.size).to be > 0 }
    it 'should build case note domain group with domain groups' do
      expect(case_note.case_note_domain_groups.map(&:domain_group)).to include(domain_group)
    end
  end

  # UX round 3 (D1/R7): the domain picker contract.
  context 'populate notes is idempotent (D1)' do
    let!(:domain_group){ create(:domain_group) }
    it 'does not duplicate sections on a second call (edit / validation re-render path)' do
      case_note.populate_notes
      first_count = case_note.case_note_domain_groups.size
      case_note.populate_notes
      expect(case_note.case_note_domain_groups.size).to eq(first_count)
    end
  end

  context 'blank domain sections are rejected (D1)' do
    let!(:domain_group){ create(:domain_group) }
    let!(:other_group){ create(:domain_group) }

    it 'persists only the filled section when attrs for every group are submitted' do
      note = create(:case_note)
      note.update(case_note_domain_groups_attributes: {
                    '0' => { domain_group_id: domain_group.id, note: 'we discussed housing' },
                    '1' => { domain_group_id: other_group.id, note: '' }
                  })
      expect(note.case_note_domain_groups.count).to eq(1)
      expect(note.case_note_domain_groups.first.domain_group).to eq(domain_group)
    end

    it 'keeps an EXISTING row even when its fields post blank (deselect hides, never deletes)' do
      note = create(:case_note)
      row  = create(:case_note_domain_group, domain_group: domain_group, case_note: note, note: 'existing body')
      note.update(case_note_domain_groups_attributes: { '0' => { id: row.id, domain_group_id: domain_group.id } })
      expect(note.case_note_domain_groups.count).to eq(1)
      expect(row.reload.note).to eq('existing body')
    end
  end

  context 'complete_tasks skips rejected/missing sections (D1)' do
    let!(:domain_group){ create(:domain_group) }
    it 'no-ops for a domain group with no persisted row instead of raising' do
      expect do
        case_note.complete_tasks({ '0' => { domain_group_id: domain_group.id, task_ids: [] } })
      end.not_to raise_error
    end

    it 'tolerates nil params (all sections deselected)' do
      expect { case_note.complete_tasks(nil) }.not_to raise_error
    end
  end

  context 'complete tasks' do
    let!(:domain_group){ create(:domain_group) }
    let!(:case_note_domain_group){ create(:case_note_domain_group, domain_group: domain_group, case_note: case_note) }
    let!(:task){ create(:task) }
    let!(:other_task){ create(:task) }
    let!(:task_ids){ [task.id, other_task.id] }
    before do
      case_note.complete_tasks(
        {"0"=>
          {
            domain_group_id: domain_group.id,
            task_ids: task_ids
          }
      })
      task.reload
    end
    it{ expect(task.completed?).to be_truthy }
    it 'should have case note domain group association with task' do
      expect(case_note_domain_group.tasks).to include(task)
    end
  end
end

describe CaseNote, 'scopes' do
  let!(:case_note){ create(:case_note) }
  let!(:latest_case_note){ create(:case_note) }

  context 'most recents' do
    it 'should have first object as the latest case note' do
      expect(CaseNote.most_recents.first).to eq(latest_case_note)
    end
    it 'should not have first object not the latest case note' do
      expect(CaseNote.most_recents.first).not_to eq(case_note)
    end
  end
end

describe CaseNote, 'callbacks' do
  let!(:client){ create(:client) }
  let!(:assessment){create(:assessment, created_at: Time.now - 6.month - 1.day, client: client)}
  let!(:latest_assessment){create(:assessment, client: client)}
  let!(:case_note){ create(:case_note, client: client)}
  let!(:other_client){ create(:client) }
  let!(:other_assessment){create(:assessment, client: other_client)}
  
  it 'should set assessment to latest assessment' do
    expect(case_note.assessment).to eq(latest_assessment)
  end
  it 'should not set assessment to not latest assessment' do
    expect(case_note.assessment).not_to eq(assessment)
  end
  it 'should not set assessment to latest assessment of other client' do
    expect(case_note.assessment).not_to eq(other_assessment)
  end
end