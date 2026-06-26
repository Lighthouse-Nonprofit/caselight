describe Domain, 'associations' do
  it { is_expected.to belong_to(:domain_group) }
  it { is_expected.to have_many(:assessment_domains).dependent(:restrict_with_error)}
  it { is_expected.to have_many(:tasks).dependent(:restrict_with_error)}
end

describe Domain, 'validations' do
  it { is_expected.to validate_presence_of(:name) }
  it { is_expected.to validate_presence_of(:identity) }
  it { is_expected.to validate_presence_of(:domain_group) }

  it { is_expected.to validate_uniqueness_of(:name).case_insensitive }
  it { is_expected.to validate_uniqueness_of(:identity).case_insensitive }

  it { is_expected.to validate_presence_of(:sensitivity) }
  it { is_expected.to validate_inclusion_of(:sensitivity).in_array(Domain::SENSITIVITY_LEVELS) }
end

describe Domain, 'sensitivity (Phase 5.2b / AC-6)' do
  it 'defaults to standard' do
    expect(Domain.new.sensitivity).to eq('standard')
  end

  it 'exposes the three locked levels' do
    expect(Domain::SENSITIVITY_LEVELS).to eq(%w[standard restricted emergency_only])
  end

  describe 'scopes' do
    let!(:std) { create(:domain, sensitivity: 'standard') }
    let!(:res) { create(:domain, sensitivity: 'restricted') }
    let!(:eme) { create(:domain, sensitivity: 'emergency_only') }

    it { expect(Domain.standard).to include(std) }
    it { expect(Domain.standard).not_to include(res, eme) }
    it { expect(Domain.restricted).to contain_exactly(res) }
    it { expect(Domain.emergency_only).to contain_exactly(eme) }
    it { expect(Domain.by_sensitivity('restricted')).to contain_exactly(res) }
  end
end
