# frozen_string_literal: true
require 'rails_helper'

# POAM-017b FOLLOW-THROUGH GUARD — the transitional jquery-migrate 3.5.2 bridge is out
# (R13). It was load-bearing for exactly one removed-in-jQuery-3 API: the $(window).load()
# event alias (9 sites, converted to $(window).on('load', ...)). Everything else the R5
# smoke's JQMIGRATE triage surfaced was deprecated-but-functional 1.x idiom in vendored
# plugins (bind/hover/shorthands/isFunction/isArray/expr-pseudos) — jQuery-4 concerns that
# need no bridge on 3.7. Mirrors the highcharts/tinymce/coffee/select2/moment guards.
RSpec.describe 'jquery-migrate removal guard (POAM-017b follow-through)' do
  ROOT = Rails.root

  it 'has no vendored jquery-migrate asset and no require for it' do
    offenders = Dir.glob(ROOT.join('vendor', 'assets', '**', '*jquery-migrate*'))
    expect(offenders).to be_empty, "vendored jquery-migrate found: #{offenders.join(', ')}"

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery-migrate}),
      'application.js still requires jquery-migrate'
    expect(manifest).to match(%r{^//=\s*require\s+jquery3$}),
      'application.js must keep requiring the jquery3 asset'
  end

  it 'has no removed-in-jQuery-3 API usage that migrate was restoring' do
    # the APIs jquery-migrate 3.x actually restores; without the bridge these throw.
    # NB: any-arg-form .load( — the first sweep matched only .load(function and missed
    # an arrow-function site in common.js that threw on every page of the smoke.
    pattern = /\$\(window\)\.load\(|\.andSelf\(|\bparseJSON\b|\$\(window\)\.unload\(/
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(pattern) }
    end
    expect(offenders).to be_empty,
      "removed-in-jQuery-3 API usage found (no migrate bridge to restore it): #{offenders.join(', ')}"
  end
end
