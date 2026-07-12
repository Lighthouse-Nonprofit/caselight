# frozen_string_literal: true
require 'rails_helper'

# jQuery version + compat guard. History: R5 rode jquery-migrate 3.5.2 as the 1.x->3 bridge;
# R13 removed it. R12D moved to jQuery 4.0 (vendored) and deliberately reintroduced the bridge
# as jquery-migrate 4.0.2. The bridge is now REMOVED AGAIN (the post-CSP-soak cleanup): a
# full-surface JQMIGRATE sweep showed the shipped 4.0 core still defines the event shorthands
# and .bind/.hover/.unbind (deprecated but working), and the only genuinely-removed APIs with
# live callers are restored by app/assets/javascripts/jquery4_compat.js — an explicit,
# census-driven, four-entry compat file. This spec bans the bridge's return AND pins the
# compat file so it cannot silently grow into a new migrate.
RSpec.describe 'jQuery 4 + compat guard (post-migrate-removal)' do
  ROOT = Rails.root

  it 'ships vendored jQuery 4 with the migrate bridge gone and the compat file wired' do
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/jquery4.min.js'))).to be(true)
    expect(File.read(ROOT.join('vendor/assets/javascripts/jquery4.min.js'), encoding: 'UTF-8'))
      .to include('jQuery v4.0')
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/jquery-migrate.js'))).to be(false)

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+jquery4\.min$})
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery-migrate$})
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery3$})
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery$})
    # compat must load immediately after core, before any plugin that calls a restored API
    core_i   = manifest.lines.index { |l| l =~ %r{^//=\s*require\s+jquery4\.min$} }
    compat_i = manifest.lines.index { |l| l =~ %r{^//=\s*require\s+jquery4_compat$} }
    expect(compat_i).not_to be_nil, 'application.js must require jquery4_compat'
    expect(compat_i).to eq(core_i + 1), 'jquery4_compat must load directly after jquery4.min'

    gemfile = File.read(ROOT.join('Gemfile')).lines.reject { |l| l.strip.start_with?('#') }.join
    expect(gemfile).not_to include("gem 'jquery-rails'")
  end

  it 'pins the compat file to exactly the censused restorations (no creeping migrate rebuild)' do
    compat = File.read(ROOT.join('app/assets/javascripts/jquery4_compat.js'), encoding: 'UTF-8')
    defined_apis = compat.scan(/jQuery\.(\w+)\s*=\s*jQuery\.\1\s*\|\|/).flatten.sort
    expect(defined_apis).to eq(%w[camelCase isFunction proxy trim]),
      "jquery4_compat.js defines #{defined_apis.inspect} — additions need a fresh caller census + this pin updated"
    # every restoration must defer to core (jQuery.x = jQuery.x || ...) — asserted by the scan
    # shape above — and nothing may attach to jQuery.fn (shorthands live in core, deprecated)
    expect(compat).not_to include('jQuery.fn.')
  end

  it 'has no removed-API usage in app javascripts (3.0 and 4.0 removals alike)' do
    # 3.0 removals (never bridged): the $(window).load/unload aliases, andSelf, parseJSON.
    # 4.0 removals restored for VENDORED plugins by jquery4_compat: banned in app code so
    # they cannot creep back — app code uses the modern forms.
    pattern = /
      \$\(window\)\.load\( | \$\(window\)\.unload\( | \.andSelf\( | \bparseJSON\b |
      \$\.trim\( | \$\.proxy\b | \$\.unique\( | \.bind\(\s*['"] | \.hover\(
    /x
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      next false if File.basename(f).end_with?('.min.js') # vendored-in-app minified plugins
      next false if File.basename(f) == 'jquery4_compat.js' # the censused restorations themselves

      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(pattern) }
    end
    expect(offenders).to be_empty,
      "removed-jQuery-API usage found in app code: #{offenders.join(', ')}"
  end
end
