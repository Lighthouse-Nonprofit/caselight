# frozen_string_literal: true
require 'rails_helper'

# OCA feedback 2026-08-26 — Araceli's program list nests curricula under a top-level program.
# The Casebook import flattened them, which is what made the list look cluttered and her list look
# inconsistent with the system. Curricula stay ProgramStreams (per-curriculum enrollment backs the
# cohort roster, roll call, Session Attendance and Cohorts::SESSION_TOTALS) and simply gain a parent.
RSpec.describe 'ProgramStream curriculum nesting', type: :model do
  let(:parent) { create(:program_stream, name: '¡Por Vida!') }

  describe 'the association' do
    it 'nests a curriculum under a top-level program' do
      child = create(:program_stream, name: 'Girasol', parent: parent)

      expect(child.parent).to eq(parent)
      expect(parent.curricula).to include(child)
      expect(ProgramStream.top_level).to include(parent)
      expect(ProgramStream.top_level).not_to include(child)
    end

    it 'leaves curricula behind rather than destroying them if a parent is removed' do
      child = create(:program_stream, name: 'Girasol', parent: parent)
      parent.destroy

      expect(ProgramStream.exists?(child.id)).to be true
      expect(child.reload.parent_id).to be_nil
    end
  end

  describe 'name uniqueness is scoped to the parent' do
    # OCA runs "Mentorship" and "Groups" under BOTH ¡Por Vida! and R.A.I.C.E.S.
    it 'allows the same curriculum name under two different parents' do
      raices = create(:program_stream, name: 'R.A.I.C.E.S.')
      create(:program_stream, name: 'Mentorship', parent: parent)

      second = build(:program_stream, name: 'Mentorship', parent: raices)
      expect(second).to be_valid
    end

    it 'still rejects a duplicate name under the SAME parent' do
      create(:program_stream, name: 'Mentorship', parent: parent)
      expect(build(:program_stream, name: 'Mentorship', parent: parent)).not_to be_valid
    end

    it 'still rejects a duplicate top-level name' do
      parent # `let` is lazy — force the original into the DB or there is nothing to collide with
      expect(build(:program_stream, name: '¡Por Vida!')).not_to be_valid
    end
  end

  describe 'cycle protection' do
    it 'refuses to make a program its own parent' do
      parent.parent_id = parent.id
      expect(parent).not_to be_valid
      expect(parent.errors[:parent_id].join).to match(/itself/)
    end

    it 'refuses a circular nesting' do
      child = create(:program_stream, name: 'Girasol', parent: parent)
      parent.parent = child

      expect(parent).not_to be_valid
      expect(parent.errors[:parent_id].join).to match(/circular/)
    end
  end

  # The whole point of keeping curricula as ProgramStreams: the cohort machinery must be untouched.
  describe 'nesting does not disturb the cohort machinery' do
    it 'keeps a nested curriculum enrollable and visible to Cohorts' do
      child = create(:program_stream, name: 'Girasol', parent: parent, quantity: nil)
      create(:tracking, program_stream: child, name: Cohorts::SESSION_TRACKING)
      client = create(:client)

      enrollment = create(:client_enrollment, client: client, program_stream: child, status: 'Active',
                                              properties: { 'e-mail' => 'a@b.test', 'age' => '3',
                                                            'description' => 'x' })

      expect(Cohorts.programs).to include(child)
      expect(child.client_enrollments).to include(enrollment)
      expect(child.enroll?(client)).to be false # already active in this cohort
    end
  end
end
