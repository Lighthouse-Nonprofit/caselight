# frozen_string_literal: true
require 'rails_helper'

describe ProgressNoteType, 'associations' do
  it { is_expected.to have_many(:progress_notes).dependent(:restrict_with_error) }
end

describe ProgressNoteType, 'validations' do
  it { is_expected.to validate_presence_of(:note_type) }
  it { is_expected.to validate_uniqueness_of(:note_type).case_insensitive }
end

describe ProgressNoteType, 'methods' do
  let!(:location) { create(:location, name: 'ផ្សេងៗ Other') }
  let!(:progress_note_type) { create(:progress_note_type) }
  let!(:used_progress_note_type) { create(:progress_note_type) }
  let!(:progress_note) { create(:progress_note, progress_note_type: used_progress_note_type, location: location) }
end

# Bifurcated note families (OCA 2026-08): a ProgressNoteType belongs to one of Contact / Curriculum /
# General, which drives the grouped picker + the Notes-tab family filter.
RSpec.describe ProgressNoteType, type: :model do
  it 'defaults new types to the contact family' do
    expect(create(:progress_note_type).category).to eq('contact')
  end

  it 'rejects an unknown category' do
    t = build(:progress_note_type, category: 'nonsense')
    expect(t).not_to be_valid
    expect(t.errors[:category]).to be_present
  end

  describe 'family scopes' do
    let!(:contact)    { create(:progress_note_type, category: 'contact') }
    let!(:curriculum) { create(:progress_note_type, category: 'curriculum') }
    let!(:general)    { create(:progress_note_type, category: 'general') }

    it 'partitions by family' do
      expect(described_class.contact).to include(contact)
      expect(described_class.curriculum).to contain_exactly(curriculum)
      expect(described_class.general).to contain_exactly(general)
    end
  end

  describe '.grouped_by_category' do
    it 'returns ordered [label, types] pairs and omits empty families' do
      create(:progress_note_type, note_type: 'Phone call', category: 'contact')
      create(:progress_note_type, note_type: 'Curriculum / Session', category: 'curriculum')
      # no general rows -> the General group must not appear
      groups = described_class.grouped_by_category
      labels = groups.map(&:first)
      expect(labels).to eq(['Contact', 'Curriculum & Activity']) # General omitted, contact before curriculum
      expect(groups.first.last).to all(be_a(described_class))
    end
  end

  it 'labels its family for display' do
    expect(build(:progress_note_type, category: 'curriculum').category_label).to eq('Curriculum & Activity')
  end
end
