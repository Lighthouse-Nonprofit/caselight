# frozen_string_literal: true
require 'rails_helper'

# POAM-004 Unit 2 — the shared safe-deserialization module that replaced Kernel#eval in the
# paper_trail version-history render path. Proves: real shapes parse correctly (byte-identical to what
# the old eval produced when rendered), empty/nil shapes -> nil (so the view's `next if values=='{}'`
# and present? guards keep behaving), and a MALICIOUS ruby string is rendered INERT (never executed).
# NOTE (folds review fix): parse() is inert-by-not-executing; a ruby-looking plain scalar such as
# 'system("x")' is a valid YAML scalar and returns the RAW STRING (not nil). The security property is
# that no code runs — asserted via an untouched module-global marker — NOT that every string -> nil.
RSpec.describe SafeVersionValue do
  describe '.parse' do
    it 'passes an already-deserialized Hash through unchanged (the live path — byte-identical)' do
      h = { 'Mental Health Needs' => 'Supervised care' }
      expect(SafeVersionValue.parse(h)).to equal(h)
    end

    it 'passes an already-deserialized Array of Hashes through unchanged' do
      a = [{ 'name' => 'provider', 'type' => 'text' }]
      expect(SafeVersionValue.parse(a)).to equal(a)
    end

    it 'parses a JSON object string to a string-keyed Hash (enrollment/tracking properties shape)' do
      json = '{"School":"Local Elementary","Grade":"2nd"}'
      expect(SafeVersionValue.parse(json)).to eq('School' => 'Local Elementary', 'Grade' => '2nd')
    end

    it 'parses a JSON array-of-objects string (program_stream enrollment shape)' do
      json = '[{"name":"provider","type":"text","label":"Provider"}]'
      expect(SafeVersionValue.parse(json)).to eq([{ 'name' => 'provider', 'type' => 'text', 'label' => 'Provider' }])
    end

    it 'parses the Tier-5 encrypted-envelope JSON to a Hash (harmless; masking happens upstream)' do
      env = '{"p":"Ff4=","h":{"iv":"ZsiNBCgEijRurJ3n","at":"kmuKTW2KiuKwB4n3LXhCsw=="}}'
      expect(SafeVersionValue.parse(env)).to eq('p' => 'Ff4=', 'h' => { 'iv' => 'ZsiNBCgEijRurJ3n', 'at' => 'kmuKTW2KiuKwB4n3LXhCsw==' })
    end

    it 'parses a YAML mapping string via the YAML.safe_load fallback' do
      yaml = "---\nSchool: Local Elementary\n"
      expect(SafeVersionValue.parse(yaml)).to eq('School' => 'Local Elementary')
    end

    it 'returns nil for nil, empty, {} and [] (matches the view empty-guards)' do
      expect(SafeVersionValue.parse(nil)).to be_nil
      expect(SafeVersionValue.parse('')).to be_nil
      expect(SafeVersionValue.parse('   ')).to be_nil
      expect(SafeVersionValue.parse('{}')).to be_nil
      expect(SafeVersionValue.parse('[]')).to be_nil
    end

    it 'renders a malicious code string INERT — never executes it (result is inert data, marker untouched)' do
      $poam004_marker = :untouched
      ['$poam004_marker = :EXECUTED', 'system("echo pwned")', 'Kernel.exit!', %q{`echo pwned`}].each do |payload|
        result = nil
        expect { result = SafeVersionValue.parse(payload) }.not_to raise_error
        expect(result).to be_a(String).or be_nil
      end
      expect($poam004_marker).to eq(:untouched)
    end

    it 'never raises on garbage / YAML-tagged input (returns inert value)' do
      ['{not json', '!!ruby/object:Foo {}', "---\n- !ruby/hash:BadClass {}"].each do |bad|
        expect { SafeVersionValue.parse(bad) }.not_to raise_error
      end
    end
  end
end
