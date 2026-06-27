require 'rails_helper'

# Phase 5.3 (NIST AC-6) — Assessment#assessment_domains_score(levels), #visible_assessment_domains,
# and #basic_info(levels) mask the assessment_domains JOIN by domains.sensitivity. Proves masking for
# non-permitted AND no over-mask for admin when the full level set is threaded.
describe Assessment, 'domain-score masking (Phase 5.3 / AC-6)' do
  let(:client)     { create(:client) }
  let(:assessment) { create(:assessment, client: client) }

  let!(:d_std) { create(:domain, sensitivity: 'standard') }
  let!(:d_res) { create(:domain, sensitivity: 'restricted') }
  let!(:d_emg) { create(:domain, sensitivity: 'emergency_only') }

  let!(:ad_std) { create(:assessment_domain, assessment: assessment, domain: d_std, score: 1) }
  let!(:ad_res) { create(:assessment_domain, assessment: assessment, domain: d_res, score: 2) }
  let!(:ad_emg) { create(:assessment_domain, assessment: assessment, domain: d_emg, score: 3) }

  describe '#assessment_domains_score' do
    it 'standard-only viewer sees only the standard score + a hidden marker' do
      out = assessment.assessment_domains_score(['standard'])
      expect(out).to include("#{d_std.name}: 1")
      expect(out).not_to include("#{d_res.name}: 2")
      expect(out).to include('2 restricted hidden')
    end

    it 'restricted-role viewer sees standard + restricted, emergency hidden' do
      out = assessment.assessment_domains_score(['standard', 'restricted'])
      expect(out).to include("#{d_std.name}: 1", "#{d_res.name}: 2")
      expect(out).not_to include("#{d_emg.name}: 3")
      expect(out).to include('1 restricted hidden')
    end

    it 'admin (all levels) sees everything with NO hidden marker (no over-mask)' do
      out = assessment.assessment_domains_score(['standard', 'restricted', 'emergency_only'])
      expect(out).to include("#{d_std.name}: 1", "#{d_res.name}: 2", "#{d_emg.name}: 3")
      expect(out).not_to include('restricted hidden')
    end

    it 'defaults to standard-only (fail-closed) when no levels passed' do
      out = assessment.assessment_domains_score
      expect(out).to include("#{d_std.name}: 1")
      expect(out).not_to include("#{d_res.name}: 2")
    end
  end

  describe '#visible_assessment_domains' do
    it 'returns only assessment_domains at a visible level' do
      expect(assessment.visible_assessment_domains(['standard'])).to contain_exactly(ad_std)
      expect(assessment.visible_assessment_domains(['standard', 'restricted'])).to contain_exactly(ad_std, ad_res)
    end
  end

  describe '#basic_info' do
    it 'forwards the visible levels into the summary string' do
      expect(assessment.basic_info(['standard'])).to include("#{d_std.name}: 1")
      expect(assessment.basic_info(['standard'])).not_to include("#{d_res.name}: 2")
    end
  end
end
