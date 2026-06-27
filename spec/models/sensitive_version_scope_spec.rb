require 'rails_helper'

# Phase 5.3 (NIST AC-6) — SensitiveVersionScope filters a PaperTrail::Version collection by the same
# SensitivityPolicy as every other read path, keyed per-row on custom_field_id (via the live item).
# Versions are created EXPLICITLY here (not via PaperTrail callbacks) so the test is deterministic
# regardless of whether versioning is enabled for the suite.
describe SensitiveVersionScope, '(Phase 5.3)' do
  let!(:std) { create(:custom_field, sensitivity: 'standard') }
  let!(:res) { create(:custom_field, sensitivity: 'restricted') }
  let!(:emg) { create(:custom_field, sensitivity: 'emergency_only') }

  let(:admin)      { create(:user, roles: 'admin') }
  let(:overviewer) { create(:user, roles: 'strategic overviewer') }
  let(:worker)     { create(:user, roles: 'case worker') }

  let!(:client) { create(:client) }

  before do
    @p_std = create(:custom_field_property, custom_field: std, custom_formable: client)
    @p_res = create(:custom_field_property, custom_field: res, custom_formable: client)
    @p_emg = create(:custom_field_property, custom_field: emg, custom_formable: client)
    [@p_std, @p_res, @p_emg].each do |cfp|
      PaperTrail::Version.create!(item_type: 'CustomFieldProperty', item_id: cfp.id, event: 'update')
    end
  end
  after { ClientHistory.delete_all }

  let(:cfp_versions) { PaperTrail::Version.where(item_type: 'CustomFieldProperty') }

  def cf_ids(versions)
    versions.map { |v| SensitiveVersionScope.custom_field_id_for(v) }.compact
  end

  it 'admin keeps all CFP versions' do
    expect(cf_ids(SensitiveVersionScope.filter_versions(cfp_versions, user: admin)))
      .to include(std.id, res.id, emg.id)
  end

  it 'overviewer drops restricted + emergency CFP versions' do
    ids = cf_ids(SensitiveVersionScope.filter_versions(cfp_versions, user: overviewer))
    expect(ids).to include(std.id)
    expect(ids).not_to include(res.id, emg.id)
  end

  it 'case_worker keeps standard + restricted, drops emergency' do
    ids = cf_ids(SensitiveVersionScope.filter_versions(cfp_versions, user: worker))
    expect(ids).to include(std.id, res.id)
    expect(ids).not_to include(emg.id)
  end

  it 'nil user => empty (fail-closed)' do
    expect(SensitiveVersionScope.filter_versions(cfp_versions, user: nil)).to be_empty
  end

  it 'visible_version_ids returns surviving version ids as an Array' do
    ids = SensitiveVersionScope.visible_version_ids(cfp_versions, user: overviewer)
    expect(ids).to be_an(Array)
    expect(ids.size).to eq(SensitiveVersionScope.filter_versions(cfp_versions, user: overviewer).size)
  end

  it 'non-CFP versions always pass through' do
    v = PaperTrail::Version.create!(item_type: 'Client', item_id: client.id, event: 'update')
    survivors = SensitiveVersionScope.filter_versions(PaperTrail::Version.where(item_type: 'Client'), user: overviewer)
    expect(survivors.map(&:id)).to include(v.id)
  end
end
