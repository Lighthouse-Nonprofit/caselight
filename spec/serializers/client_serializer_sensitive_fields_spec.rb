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
