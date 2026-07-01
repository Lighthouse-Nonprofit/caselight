# frozen_string_literal: true
require 'rails_helper'

# POAM-004 Unit 2 (CRITICAL / live RCE) — the parser that replaced eval() on the raw
# custom_form_selected / program_selected advanced-search hidden-field params. Proves the legit
# "[id,id,...]" payload yields the SAME integer array the old eval produced, and that an injected
# code payload is now [] (no execution).
RSpec.describe AdvancedSearches::IdList do
  describe '.parse' do
    it 'parses the legit bracketed id-list to the same Integer array eval produced' do
      expect(AdvancedSearches::IdList.parse('[8,12,15]')).to eq([8, 12, 15])
      expect(AdvancedSearches::IdList.parse('[3]')).to eq([3])
    end

    it 'returns [] for blank / empty / malformed input' do
      expect(AdvancedSearches::IdList.parse('')).to eq([])
      expect(AdvancedSearches::IdList.parse(nil)).to eq([])
      expect(AdvancedSearches::IdList.parse('[]')).to eq([])
      expect(AdvancedSearches::IdList.parse('not-an-array')).to eq([])
    end

    it 'rejects a non-integer / non-array payload as [] (no coercion surprises)' do
      expect(AdvancedSearches::IdList.parse('["1","x"]')).to eq([])
      expect(AdvancedSearches::IdList.parse('{"a":1}')).to eq([])
    end

    it 'renders an injected code payload INERT — [] and no execution' do
      $poam004_idlist_marker = :untouched
      expect(AdvancedSearches::IdList.parse('$poam004_idlist_marker = :EXECUTED; [1]')).to eq([])
      expect(AdvancedSearches::IdList.parse(%q{`echo pwned`})).to eq([])
      expect(AdvancedSearches::IdList.parse('system("echo pwned")')).to eq([])
      expect($poam004_idlist_marker).to eq(:untouched)
    end
  end
end
