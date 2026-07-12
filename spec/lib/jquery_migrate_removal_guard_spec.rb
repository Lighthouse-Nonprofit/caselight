# frozen_string_literal: true
require 'rails_helper'

# jQuery version + migrate-bridge guard. History: R5 rode jquery-migrate 3.5.2 as the 1.x→3
# bridge; R13 removed it after proving the only load-bearing restoration ($(window).load) was
# fixed at all 10 sites. R12D moves to jQuery 4.0 (vendored — the jquery-rails gem shipped no
# jquery4 asset and left with the bump) and DELIBERATELY reintroduces the bridge on the new
# major: jquery-migrate 4.0.2 restores/warns the APIs 4.0 removed that the aging vendored
# plugin set still uses. The bridge is tracked-temporary again — its removal is the post-CSP-
# soak cleanup, gated on a warning-free smoke, and this spec flips back to banning it then.
RSpec.describe 'jQuery 4 + migrate bridge guard (R12D)' do
  ROOT = Rails.root

  it 'ships vendored jQuery 4 and the migrate-4 bridge, with the gem-era assets gone' do
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/jquery4.min.js'))).to be(true)
    expect(File.read(ROOT.join('vendor/assets/javascripts/jquery4.min.js'), encoding: 'UTF-8'))
      .to include('jQuery v4.0')
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/jquery-migrate.js'))).to be(true)
    expect(File.read(ROOT.join('vendor/assets/javascripts/jquery-migrate.js'), encoding: 'UTF-8'))
      .to include('jQuery Migrate - v4')

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+jquery4\.min$})
    expect(manifest).to match(%r{^//=\s*require\s+jquery-migrate$})
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery3$})
    expect(manifest).not_to match(%r{^//=\s*require\s+jquery$})

    gemfile = File.read(ROOT.join('Gemfile')).lines.reject { |l| l.strip.start_with?('#') }.join
    expect(gemfile).not_to include("gem 'jquery-rails'")
  end

  it 'has no removed-API usage in app javascripts (3.0 and 4.0 removals alike)' do
    # 3.0 removals (never bridged by migrate-4): the $(window).load/unload aliases, andSelf,
    # parseJSON. 4.0 removals fixed in R12D and banned so they cannot creep back into APP
    # code (vendored plugins ride the migrate bridge until its removal): $.trim, $.proxy,
    # $.unique, string-event .bind(, .hover(.
    pattern = /
      \$\(window\)\.load\( | \$\(window\)\.unload\( | \.andSelf\( | \bparseJSON\b |
      \$\.trim\( | \$\.proxy\b | \$\.unique\( | \.bind\(\s*['"] | \.hover\(
    /x
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      next false if File.basename(f).end_with?('.min.js') # vendored-in-app minified plugins ride the bridge

      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(pattern) }
    end
    expect(offenders).to be_empty,
      "removed-jQuery-API usage found in app code: #{offenders.join(', ')}"
  end
end
