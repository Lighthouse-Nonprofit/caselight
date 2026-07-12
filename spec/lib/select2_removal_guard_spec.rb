# frozen_string_literal: true
require 'rails_helper'

# POAM-017c REGRESSION GUARD — select2 3.5.2 (hand-vendored, 2014) is out; Tom Select 2.x
# is the select widget, always via the CIF.Select adapter. Mirrors the highcharts/tinymce/
# coffee removal guards. NB the `.select2` CSS CLASS survives deliberately — it is the
# init-hook selector on ~18 haml forms (documented in shared/select_widget.js), so this
# guard bans the select2 ASSETS and its JS API/event surface, not the class name.
RSpec.describe 'select2 removal guard (POAM-017c)' do
  ROOT = Rails.root

  it 'has no vendored select2 assets' do
    offenders = Dir.glob(ROOT.join('vendor', 'assets', '**', '*select2*'))
    expect(offenders).to be_empty, "vendored select2 assets found: #{offenders.join(', ')}"
  end

  it 'has no select2 JS API or event usage in app javascripts' do
    pattern = /\.select2\(|select2-selecting|select2-removed|select2-close|select2-selected|select2-chosen/
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      # strip line comments so the adapter's select2->TomSelect mapping docs don't trip the guard
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(pattern) }
    end
    expect(offenders).to be_empty,
      "select2 API/event usage found (use the CIF.Select adapter): #{offenders.join(', ')}"
  end

  it 'keeps the Tom Select replacement wired' do
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/tom-select.js'))).to be(true)
    expect(File.exist?(ROOT.join('vendor/assets/stylesheets/tom-select.scss'))).to be(true)
    expect(File.exist?(ROOT.join('app/assets/javascripts/shared/select_widget.js'))).to be(true)

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+tom-select$})
    expect(manifest).to match(%r{^//=\s*require\s+shared/select_widget$})
    expect(manifest).not_to match(%r{^//=\s*require\s+select2$})

    stylesheet = File.read(ROOT.join('app/assets/stylesheets/application.scss'))
    expect(stylesheet).to include("@import 'tom-select';")
    # POAM-017g flip: the tom_select_bs3 shim was replaced by the Tom Select Bootstrap-5 theme.
    expect(stylesheet).to include("@import 'tom-select.bootstrap5';")
    expect(stylesheet).not_to match(/@import 'select2/)
  end
end
