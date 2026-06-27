require 'rails_helper'

# Phase 5.3 (NIST AC-6) — SensitivityPolicy#visible_domain_levels + #can_see_domain?
# (the domains.sensitivity axis, the assessment-side mirror of #visible_levels).
describe SensitivityPolicy, 'domain levels (Phase 5.3 / AC-6)' do
  STD = 'standard'.freeze
  RES = 'restricted'.freeze
  EMG = 'emergency_only'.freeze

  def levels_for(role)
    SensitivityPolicy.new(build(:user, roles: role)).visible_domain_levels
  end

  it 'admin sees all three levels' do
    expect(SensitivityPolicy.new(build(:user, roles: 'admin')).visible_domain_levels)
      .to match_array([STD, RES, EMG])
  end

  it 'strategic_overviewer sees standard only' do
    expect(levels_for('strategic overviewer')).to eq([STD])
  end

  it 'each restricted role sees standard + restricted, never emergency' do
    ['case worker', 'able manager', 'ec manager', 'fc manager', 'kc manager', 'manager'].each do |role|
      levels = levels_for(role)
      expect(levels).to contain_exactly(STD, RES)
      expect(levels).not_to include(EMG)
    end
  end

  it 'nil user falls back to standard only (fail-safe)' do
    expect(SensitivityPolicy.new(nil).visible_domain_levels).to eq([STD])
  end

  describe '#can_see_domain?' do
    let(:cw) { SensitivityPolicy.new(build(:user, roles: 'case worker')) }

    it 'accepts a Domain' do
      expect(cw.can_see_domain?(build(:domain, sensitivity: RES))).to be true
      expect(cw.can_see_domain?(build(:domain, sensitivity: EMG))).to be false
    end

    it 'accepts a raw level string' do
      expect(cw.can_see_domain?('standard')).to be true
      expect(cw.can_see_domain?('emergency_only')).to be false
    end

    it 'is fail-closed for nil' do
      expect(cw.can_see_domain?(nil)).to be false
    end
  end
end
