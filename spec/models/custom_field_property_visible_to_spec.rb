require 'rails_helper'

# Phase 5.3 (NIST AC) — CustomFieldProperty.visible_custom_field_ids delegate + .visible_to scope.
describe CustomFieldProperty, 'visible_to / visible_custom_field_ids (Phase 5.3)' do
  let!(:std) { create(:custom_field, sensitivity: 'standard') }
  let!(:res) { create(:custom_field, sensitivity: 'restricted') }
  let!(:emg) { create(:custom_field, sensitivity: 'emergency_only') }

  let(:admin)      { create(:user, roles: 'admin') }
  let(:overviewer) { create(:user, roles: 'strategic overviewer') }
  let(:worker)     { create(:user, roles: 'case worker') }

  describe '.visible_custom_field_ids' do
    it 'admin sees all' do
      ids = CustomFieldProperty.visible_custom_field_ids(admin)
      expect(ids).to include(std.id, res.id, emg.id)
    end

    it 'strategic_overviewer sees standard only' do
      ids = CustomFieldProperty.visible_custom_field_ids(overviewer)
      expect(ids).to include(std.id)
      expect(ids).not_to include(res.id, emg.id)
    end

    it 'case_worker sees standard + restricted, not emergency' do
      ids = CustomFieldProperty.visible_custom_field_ids(worker)
      expect(ids).to include(std.id, res.id)
      expect(ids).not_to include(emg.id)
    end

    it 'case_worker with break_glass widens to that emergency form only' do
      ids = CustomFieldProperty.visible_custom_field_ids(worker, break_glass: [emg.id])
      expect(ids).to include(std.id, res.id, emg.id)
    end

    it 'nil user => empty set (fail-closed)' do
      expect(CustomFieldProperty.visible_custom_field_ids(nil)).to eq(Set.new)
    end
  end

  describe '.visible_to scope' do
    let!(:client) { create(:client) }
    let!(:p_std) { create(:custom_field_property, custom_field: std, custom_formable: client) }
    let!(:p_res) { create(:custom_field_property, custom_field: res, custom_formable: client) }
    let!(:p_emg) { create(:custom_field_property, custom_field: emg, custom_formable: client) }
    after { ClientHistory.delete_all }

    it 'admin sees all rows' do
      expect(CustomFieldProperty.visible_to(admin)).to include(p_std, p_res, p_emg)
    end

    it 'overviewer sees only standard rows' do
      visible = CustomFieldProperty.visible_to(overviewer)
      expect(visible).to include(p_std)
      expect(visible).not_to include(p_res, p_emg)
    end

    it 'composes with by_custom_field' do
      expect(CustomFieldProperty.visible_to(worker).by_custom_field(res)).to include(p_res)
      expect(CustomFieldProperty.visible_to(overviewer).by_custom_field(res)).to be_empty
    end

    it 'nil user => none' do
      expect(CustomFieldProperty.visible_to(nil)).to be_empty
    end
  end
end
