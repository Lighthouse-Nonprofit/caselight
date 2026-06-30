# frozen_string_literal: true
require 'rails_helper'

# Phase 5.5 (AC-6) least-privilege narrowing -- Ability unit. Proves the SHADOW-FIRST contract
# at the rule layer:
#   * force_least_privilege: false (the default / flag-OFF state) => the compiled rules are
#     IDENTICAL to today (strategic_overviewer keeps :version,:all; the four manager roles keep
#     unscoped :read, ProgressNote).
#   * force_least_privilege: true (the enforce state) => strategic_overviewer is denied :version
#     AND :read DataTracker; ec/fc/kc_manager can :read a note on an own-caseload client AND a note
#     on a program-STATUS-matched (non-caseload) client, but NOT an unrelated note; manager can
#     read a team-caseload note but not an off-team note.
#   * admin + case_worker are UNCHANGED in both states.
# Lives in spec/models (a CI-covered dir) -- the legacy ability_spec.rb is in spec/features (NOT CI).
RSpec.describe Ability, type: :model do
  def caseload_client(user, attrs = {})
    c = create(:client, { able_state: 'Accepted' }.merge(attrs))
    c.users << user unless c.users.include?(user)
    c
  end

  describe 'strategic_overviewer :version + DataTracker' do
    let(:user) { create(:user, :strategic_overviewer) }

    it 'flag OFF (default): keeps org-wide version history + dashboard (byte-identical to today)' do
      ability = Ability.new(user, force_least_privilege: false)
      expect(ability.can?(:version, Client.new)).to be(true)
      expect(ability.can?(:read, DataTracker)).to be(true)
      expect(ability.can?(:read, :all)).to be(true)   # read:all intentionally LEFT broad
      expect(ability.can?(:report, :all)).to be(true) # report:all intentionally LEFT broad
    end

    it 'flag ON: denied version history + the /data_trackers dashboard, keeps record-level read' do
      ability = Ability.new(user, force_least_privilege: true)
      expect(ability.can?(:version, Client.new)).to be(false)
      expect(ability.can?(:read, DataTracker)).to be(false)
      expect(ability.can?(:read, Client.new)).to be(true)
      expect(ability.can?(:report, :all)).to be(true)
    end
  end

  {
    ec_manager: 'Active EC',
    fc_manager: 'Active FC',
    kc_manager: 'Active KC'
  }.each do |role, active_status|
    describe "#{role} :read, ProgressNote (status OR caseload union)" do
      let(:user) { create(:user, role) }

      it 'flag OFF: reads an unrelated note (unscoped, as today)' do
        off_note = create(:progress_note) # not on caseload, not the role's program status
        ability  = Ability.new(user, force_least_privilege: false)
        expect(ability.can?(:read, off_note)).to be(true)
        expect(ProgressNote.accessible_by(ability, :read)).to include(off_note)
      end

      it 'flag ON: allows an own-caseload note, a program-STATUS (non-caseload) note, and denies an unrelated note' do
        on_note     = create(:progress_note, client: caseload_client(user))
        status_note = create(:progress_note, client: create(:client, status: active_status, able_state: 'Accepted'))
        off_note    = create(:progress_note, client: create(:client, status: 'Exited', able_state: 'Accepted'))
        ability     = Ability.new(user, force_least_privilege: true)

        expect(ability.can?(:read, on_note)).to be(true)
        expect(ability.can?(:read, status_note)).to be(true) # UNION: status axis must NOT be dropped
        expect(ability.can?(:read, off_note)).to be(false)

        accessible = ProgressNote.accessible_by(ability, :read)
        expect(accessible).to include(on_note, status_note)
        expect(accessible).not_to include(off_note)
      end
    end
  end

  describe 'manager :read, ProgressNote (team scope)' do
    let(:manager)     { create(:user, :manager) }
    let(:team_member) { create(:user, :case_worker, manager_id: manager.id) }

    it 'flag OFF: reads an off-team note (unscoped, as today)' do
      off_note = create(:progress_note)
      ability  = Ability.new(manager, force_least_privilege: false)
      expect(ability.can?(:read, off_note)).to be(true)
    end

    it 'flag ON: allows a team-caseload note, denies an off-team note' do
      team_client = create(:client, able_state: 'Accepted'); team_client.users << team_member
      on_note  = create(:progress_note, client: team_client)
      off_note = create(:progress_note)
      ability  = Ability.new(manager, force_least_privilege: true)
      expect(ability.can?(:read, on_note)).to be(true)
      expect(ability.can?(:read, off_note)).to be(false)
    end
  end

  describe 'unaffected roles (both states)' do
    it 'admin keeps manage:all incl. version + DataTracker regardless of flag' do
      admin = create(:user, :admin)
      [false, true].each do |flag|
        ability = Ability.new(admin, force_least_privilege: flag)
        expect(ability.can?(:version, Client.new)).to be(true)
        expect(ability.can?(:read, DataTracker)).to be(true)
        expect(ability.can?(:read, ProgressNote.new)).to be(true)
      end
    end

    it 'case_worker ProgressNote access is unchanged by the flag (already caseload via Client)' do
      cw = create(:user, :case_worker)
      note = create(:progress_note, client: caseload_client(cw))
      [false, true].each do |flag|
        ability = Ability.new(cw, force_least_privilege: flag)
        expect(ability.can?(:manage, note)).to be(true)
      end
    end
  end

  describe '.least_privilege_enforced?' do
    it 'reads the config.x flag (default OFF)' do
      expect(Ability.least_privilege_enforced?).to be(false)
    end
  end
end
