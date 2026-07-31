# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D5 (SECURITY) — the server-side field-type allowlist. Builder JSON
# reaches `render "/shared/fields/#{type.underscore}"`; until D5 the ONLY restriction
# was formBuilder's client-side disableFields. All three JSON holders must refuse an
# unknown type at save time.
RSpec.describe FormBuilderFieldTypes do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:good_field) { { 'type' => 'text', 'label' => 'Notes', 'className' => 'form-control' } }
  let(:evil_field) { { 'type' => '../../layouts/application', 'label' => 'Sneaky' } }

  describe 'CustomField#fields' do
    it 'accepts every renderer-backed type' do
      fields = FormBuilderFieldTypes::ALLOWED_FIELD_TYPES.each_with_index.map do |type, i|
        { 'type' => type, 'label' => "Field #{i}", 'values' => [{ 'label' => 'A', 'value' => 'A' }] }
      end
      cf = CustomField.new(entity_type: 'Client', form_title: 'All types', fields: fields)
      expect(cf).to be_valid
    end

    it 'rejects a path-traversal type before it can reach the partial render' do
      cf = CustomField.new(entity_type: 'Client', form_title: 'Evil', fields: [good_field, evil_field])
      expect(cf).not_to be_valid
      expect(cf.errors[:fields].join).to include('unsupported field type')
    end

    it 'rejects an unknown-but-innocent type too (closed list, not a blocklist)' do
      cf = CustomField.new(entity_type: 'Client', form_title: 'Innocent',
                           fields: [good_field.merge('type' => 'autocomplete')])
      expect(cf).not_to be_valid
    end

    it 'accepts the underscored spellings older stored forms carry (renderer underscores anyway)' do
      fields = [
        { 'type' => 'radio_group',    'label' => 'Status', 'values' => [{ 'label' => 'Open' }] },
        { 'type' => 'checkbox_group', 'label' => 'Needs',  'values' => [{ 'label' => 'Housing' }] }
      ]
      cf = CustomField.new(entity_type: 'Client', form_title: 'Legacy spellings', fields: fields)
      expect(cf).to be_valid
    end
  end

  describe 'ProgramStream#enrollment / #exit_program' do
    it 'rejects an unknown type on either builder attribute' do
      ps = build(:program_stream)
      ps.enrollment = [evil_field]
      expect(ps).not_to be_valid
      expect(ps.errors[:enrollment].join).to include('unsupported field type')

      ps2 = build(:program_stream)
      ps2.exit_program = [evil_field]
      expect(ps2).not_to be_valid
      expect(ps2.errors[:exit_program].join).to include('unsupported field type')
    end

    it 'still accepts the factory defaults (text/number)' do
      expect(build(:program_stream)).to be_valid
    end
  end

  describe 'Tracking#fields' do
    it 'rejects an unknown type' do
      tracking = Tracking.new(name: 'Monthly', program_stream: create(:program_stream),
                              fields: [evil_field])
      expect(tracking).not_to be_valid
      expect(tracking.errors[:fields].join).to include('unsupported field type')
    end
  end
end
