# frozen_string_literal: true
require 'rails_helper'

# Phase 5.2 — CustomField sensitivity classification (NIST AC family).
RSpec.describe CustomField, 'sensitivity', type: :model do
  describe 'CONSTANT' do
    it 'defines the three ordered sensitivity levels' do
      expect(CustomField::SENSITIVITY_LEVELS).to eq(%w[standard restricted emergency_only])
    end
  end

  describe 'default + NOT NULL column' do
    it 'defaults a new form to standard' do
      cf = create(:custom_field)
      expect(cf.sensitivity).to eq('standard')
    end
  end

  describe 'validation' do
    it 'accepts each declared level' do
      CustomField::SENSITIVITY_LEVELS.each do |level|
        cf = build(:custom_field, sensitivity: level)
        expect(cf).to be_valid, "expected #{level} to be a valid sensitivity"
      end
    end

    it 'rejects an unknown level' do
      cf = build(:custom_field, sensitivity: 'top_secret')
      expect(cf).not_to be_valid
      expect(cf.errors[:sensitivity]).to be_present
    end
  end

  describe 'scopes' do
    let!(:std) { create(:custom_field, sensitivity: 'standard') }
    let!(:res) { create(:custom_field, sensitivity: 'restricted') }
    let!(:emg) { create(:custom_field, sensitivity: 'emergency_only') }

    it 'by_sensitivity filters to the given level' do
      expect(CustomField.by_sensitivity('restricted')).to contain_exactly(res)
    end

    it 'standard / restricted / emergency_only return only their level' do
      expect(CustomField.standard).to include(std)
      expect(CustomField.standard).not_to include(res, emg)
      expect(CustomField.restricted).to contain_exactly(res)
      expect(CustomField.emergency_only).to contain_exactly(emg)
    end
  end
end
