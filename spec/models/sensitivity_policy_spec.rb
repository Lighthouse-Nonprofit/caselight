# frozen_string_literal: true
require 'rails_helper'

# Phase 5.2 — SensitivityPolicy need-to-know matrix (NIST AC family). The ONE place the
# per-form visibility rule lives. KEYWORD constructor: SensitivityPolicy.new(user, active_break_glass_form_ids: []).
RSpec.describe SensitivityPolicy, type: :model do
  let!(:std_form)  { create(:custom_field, sensitivity: 'standard') }
  let!(:res_form)  { create(:custom_field, sensitivity: 'restricted') }
  let!(:emg_form)  { create(:custom_field, sensitivity: 'emergency_only') }
  let!(:emg_form2) { create(:custom_field, sensitivity: 'emergency_only') }

  def visible(user, grants = [])
    described_class.new(user, active_break_glass_form_ids: grants).visible_custom_field_ids
  end

  describe 'admin' do
    let(:user) { create(:user, roles: 'admin') }
    it 'sees every level including emergency_only without any grant' do
      expect(visible(user)).to include(std_form.id, res_form.id, emg_form.id, emg_form2.id)
    end
  end

  describe 'strategic_overviewer' do
    let(:user) { create(:user, roles: 'strategic overviewer') }
    it 'sees standard only' do
      ids = visible(user)
      expect(ids).to include(std_form.id)
      expect(ids).not_to include(res_form.id, emg_form.id)
    end
    it 'never gets emergency_only even if a grant id is (wrongly) supplied' do
      expect(visible(user, [emg_form.id])).not_to include(emg_form.id)
    end
  end

  describe 'restricted roles' do
    [['case worker'], ['able manager'], ['ec manager'], ['fc manager'], ['kc manager'], ['manager']].each do |(role)|
      context "as #{role}" do
        let(:user) { create(:user, roles: role) }

        it 'sees standard + restricted but NOT emergency_only by default' do
          ids = visible(user)
          expect(ids).to include(std_form.id, res_form.id)
          expect(ids).not_to include(emg_form.id, emg_form2.id)
        end

        it 'unlocks ONLY the emergency_only form(s) with an active break-glass grant' do
          ids = visible(user, [emg_form.id])
          expect(ids).to include(emg_form.id)
          expect(ids).not_to include(emg_form2.id)
        end
      end
    end
  end

  describe 'nil / unrecognized user' do
    it 'falls safe to standard only' do
      expect(visible(nil)).to eq(Set.new([std_form.id]))
    end
  end
end
