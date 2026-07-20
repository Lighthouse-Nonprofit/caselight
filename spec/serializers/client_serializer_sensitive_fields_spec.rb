require 'rails_helper'

# Phase 5.3 (NIST AC) — ClientSerializer gates #additional_form + #add_forms by the
# :visible_custom_field_ids instance option, and #assessments/#case_notes by :visible_domain_levels.
# Tests the serializer methods directly (the live consumer is api/clients#compare).
describe ClientSerializer, 'sensitive-field gating (Phase 5.3)' do
  let(:client) { create(:client) }
  let!(:std)   { create(:custom_field, entity_type: 'Client', sensitivity: 'standard') }
  let!(:res)   { create(:custom_field, entity_type: 'Client', sensitivity: 'restricted') }
  let!(:p_std) { create(:custom_field_property, custom_field: std, custom_formable: client) }
  let!(:p_res) { create(:custom_field_property, custom_field: res, custom_formable: client) }
  after { ClientHistory.delete_all }

  def titles(forms)
    forms.map { |f| f[:form_title] || f['form_title'] }
  end

  describe '#additional_form' do
    it 'includes only forms in the visible set' do
      s = ClientSerializer.new(client, visible_custom_field_ids: Set.new([std.id]))
      expect(titles(s.additional_form)).to include(std.form_title)
      expect(titles(s.additional_form)).not_to include(res.form_title)
    end

    it 'is empty when no visible set is passed (fail-closed)' do
      expect(ClientSerializer.new(client).additional_form).to eq([])
    end

    it 'includes both when both ids are visible' do
      s = ClientSerializer.new(client, visible_custom_field_ids: Set.new([std.id, res.id]))
      expect(titles(s.additional_form)).to include(std.form_title, res.form_title)
    end
  end

  describe '#add_forms (unfilled form titles)' do
    it 'excludes non-visible unfilled forms and includes visible ones' do
      unused_res = create(:custom_field, entity_type: 'Client', sensitivity: 'restricted')
      s_std  = ClientSerializer.new(client, visible_custom_field_ids: Set.new([std.id]))
      s_full = ClientSerializer.new(client, visible_custom_field_ids: Set.new([std.id, unused_res.id]))
      expect(s_std.add_forms.map(&:id)).not_to include(unused_res.id)
      expect(s_full.add_forms.map(&:id)).to include(unused_res.id)
    end
  end

  describe '#visible_domain_levels_option (private)' do
    it 'defaults to standard-only when the option is absent (fail-closed)' do
      expect(ClientSerializer.new(client).send(:visible_domain_levels_option)).to eq(['standard'])
    end

    it 'uses the passed domain levels' do
      s = ClientSerializer.new(client, visible_domain_levels: ['standard', 'restricted'])
      expect(s.send(:visible_domain_levels_option)).to contain_exactly('standard', 'restricted')
    end
  end
end

# Phase 5.3 (NIST AC-6) — ClientSerializer#assessments and #case_notes must MASK CSI scores whose
# Domain#sensitivity is not in the viewer's :visible_domain_levels (levels.include?(...), fail-closed to
# standard-only). Restricted-domain scores are among the most sensitive data in the app; the filter lives
# ONLY in these two methods and must also survive the SerializableResource(each_serializer:) path that the
# live consumer (api/clients#compare) renders through. Complements the #additional_form/#add_forms specs above.
describe ClientSerializer, 'domain-sensitivity masking (#assessments / #case_notes)' do
  let(:client)       { create(:client) }
  let(:domain_group) { create(:domain_group) }
  let!(:std_domain)  { create(:domain, domain_group: domain_group, sensitivity: 'standard') }
  let!(:res_domain)  { create(:domain, domain_group: domain_group, sensitivity: 'restricted') }
  let!(:assessment)  { create(:assessment, client: client) }
  let!(:ad_std)      { create(:assessment_domain, assessment: assessment, domain: std_domain) }
  let!(:ad_res)      { create(:assessment_domain, assessment: assessment, domain: res_domain) }
  after { ClientHistory.delete_all }

  # domain_ids present in the serialized payload, tolerant of symbol/string keys: a direct method call
  # returns the raw merged hashes (symbol keys from #merge, string keys from #as_json), while the
  # SerializableResource#as_json path stringifies every key.
  def assessment_domain_ids(assessments_json)
    Array(assessments_json)
      .flat_map { |a| a[:assessment_domain] || a['assessment_domain'] || [] }
      .map { |ad| ad['domain_id'] || ad[:domain_id] }
  end

  def case_note_domain_ids(case_notes_json)
    Array(case_notes_json)
      .flat_map { |cn| cn[:case_note_domain_group] || cn['case_note_domain_group'] || [] }
      .flat_map { |cdg| cdg[:domain_scores] || cdg['domain_scores'] || [] }
      .map { |ds| ds[:domain_id] || ds['domain_id'] }
  end

  describe '#assessments' do
    it 'excludes restricted-domain scores from a standard-only viewer' do
      serializer = ClientSerializer.new(client, visible_domain_levels: ['standard'])
      ids = assessment_domain_ids(serializer.assessments)
      expect(ids).to include(std_domain.id)
      expect(ids).not_to include(res_domain.id)
    end

    it 'includes restricted-domain scores when the viewer is permitted restricted' do
      serializer = ClientSerializer.new(client, visible_domain_levels: ['standard', 'restricted'])
      ids = assessment_domain_ids(serializer.assessments)
      expect(ids).to include(std_domain.id, res_domain.id)
    end
  end

  describe '#case_notes' do
    # #case_notes reads scores via domain.assessment_domains.find_by(assessment_id: case_note.assessment_id);
    # CaseNote#set_assessment forces assessment_id to the client's latest_record, which is `assessment`.
    let!(:case_note) { create(:case_note, client: client, assessment: assessment) }
    let!(:cdg)       { create(:case_note_domain_group, case_note: case_note, domain_group: domain_group) }

    it 'omits restricted-domain scores for standard-only and includes them when permitted' do
      standard_only = ClientSerializer.new(client, visible_domain_levels: ['standard'])
      permitted     = ClientSerializer.new(client, visible_domain_levels: ['standard', 'restricted'])

      standard_ids  = case_note_domain_ids(standard_only.case_notes)
      permitted_ids = case_note_domain_ids(permitted.case_notes)

      expect(standard_ids).to include(std_domain.id)
      expect(standard_ids).not_to include(res_domain.id)
      expect(permitted_ids).to include(std_domain.id, res_domain.id)
    end
  end

  describe 'via SerializableResource collection (mirrors api/clients#compare)' do
    let!(:case_note) { create(:case_note, client: client, assessment: assessment) }
    let!(:cdg)       { create(:case_note_domain_group, case_note: case_note, domain_group: domain_group) }

    def rendered(levels)
      payload = ActiveModelSerializers::SerializableResource.new(
        [client],
        each_serializer: ClientSerializer,
        adapter: :json,
        visible_domain_levels: levels
      ).as_json
      Array(payload[:clients] || payload['clients']).first
    end

    it 'propagates visible_domain_levels to the per-item serializer so restricted scores stay masked' do
      standard = rendered(['standard'])
      full     = rendered(['standard', 'restricted'])

      std_assessment_ids  = assessment_domain_ids(standard[:assessments] || standard['assessments'])
      full_assessment_ids = assessment_domain_ids(full[:assessments] || full['assessments'])
      std_case_note_ids   = case_note_domain_ids(standard[:case_notes] || standard['case_notes'])

      expect(std_assessment_ids).to include(std_domain.id)
      expect(std_assessment_ids).not_to include(res_domain.id)
      expect(full_assessment_ids).to include(std_domain.id, res_domain.id)
      expect(std_case_note_ids).not_to include(res_domain.id)
    end
  end
end
