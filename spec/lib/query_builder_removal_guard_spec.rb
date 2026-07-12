# frozen_string_literal: true
require 'rails_helper'

# POAM-017f REGRESSION GUARD (query-builder half, PR 12A) — jQuery QueryBuilder 2.5.2 + doT +
# jquery.extendext are out; doT compiled its templates via new Function and was the bundle's
# last unsafe-eval consumer. CIF.RuleBuilder (app/assets/javascripts/shared/rule_builder.js)
# renders the same DOM/serialization contract through plain DOM APIs. Mirrors the highcharts/
# tinymce/coffee/select2/moment/jquery-migrate removal guards.
RSpec.describe 'query-builder removal guard (POAM-017f)' do
  ROOT = Rails.root

  it 'has no query-builder family assets or gem' do
    offenders = Dir.glob(ROOT.join('vendor', 'assets', '**', '*'))
                   .select { |f| File.basename(f) =~ /query-builder|\bdoT\b|extendext/i }
    expect(offenders).to be_empty, "vendored query-builder family assets found: #{offenders.join(', ')}"

    # comment lines stripped — the Gemfile carries a removal-note naming the gem
    gemfile = File.read(ROOT.join('Gemfile')).lines.reject { |l| l.strip.start_with?('#') }.join
    lockfile = File.read(ROOT.join('Gemfile.lock'))
    expect(gemfile).not_to include('jquery_query_builder-rails')
    expect(lockfile).not_to include('jquery_query_builder-rails')
  end

  it 'has no queryBuilder/doT API usage in app javascripts' do
    pattern = /\.queryBuilder\(|afterCreateRuleFilters|doT\.template|\$\.extendext/
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      # strip line comments so migration-note docs don't trip the guard
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(pattern) }
    end
    expect(offenders).to be_empty,
      "queryBuilder/doT API usage found (use CIF.RuleBuilder): #{offenders.join(', ')}"
  end

  it 'keeps the RuleBuilder replacement wired and eval-free' do
    rule_builder = ROOT.join('app/assets/javascripts/shared/rule_builder.js')
    expect(File.exist?(rule_builder)).to be(true)
    expect(File.exist?(ROOT.join('app/assets/stylesheets/rule_builder.scss'))).to be(true)

    # the CSP point of the PR: the replacement must never grow dynamic code execution
    # (line comments stripped — the module's doc header names the banned tokens)
    code = File.read(rule_builder, encoding: 'UTF-8').lines.map { |l| l.sub(%r{//.*$}, '') }.join
    expect(code).not_to match(/\beval\(|new Function|\binnerHTML\b|insertAdjacentHTML/),
      'rule_builder.js must render via DOM APIs only (no eval/new Function/innerHTML)'

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+shared/rule_builder$})
    expect(manifest).not_to match(%r{^//=\s*require\s+(query-builder|doT|jquery\.extendext)$})

    stylesheet = File.read(ROOT.join('app/assets/stylesheets/application.scss'))
    expect(stylesheet).to include("@import 'rule_builder';")
    expect(stylesheet).not_to match(/@import ["']query-builder/)
  end
end
