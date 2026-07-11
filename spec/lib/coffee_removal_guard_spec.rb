# frozen_string_literal: true
require 'rails_helper'

# POAM-017e (coffee half) REGRESSION GUARD — CoffeeScript is retired: all 61 .coffee
# files were decaffeinated to ES2015+ and coffee-rails left the bundle. Mirrors the
# highcharts/tinymce removal guards: assert the retired toolchain cannot quietly return.
RSpec.describe 'CoffeeScript removal guard (POAM-017e)' do
  ROOT = Rails.root

  it 'has no .coffee files under the asset trees' do
    offenders = Dir.glob(ROOT.join('app', 'assets', '**', '*.coffee')) +
                Dir.glob(ROOT.join('vendor', 'assets', '**', '*.coffee'))
    expect(offenders).to be_empty,
      ".coffee files found (the pipeline no longer compiles CoffeeScript): #{offenders.join(', ')}"
  end

  it 'has no coffee-rails gem in the Gemfile or lockfile' do
    expect(File.read(ROOT.join('Gemfile'))).not_to match(/^\s*gem\s+['"]coffee-rails['"]/)
    expect(File.read(ROOT.join('Gemfile.lock'))).not_to match(/coffee-rails|coffee-script/)
  end

  it 'keeps the converted page modules wired (spot-check the dispatcher chain)' do
    # The app-wide dispatcher and the largest converted modules must exist as .js
    # (sprockets requires are extensionless, so a silent deletion would only surface
    # at runtime as dead pages).
    %w[
      initializer common
      clients/index clients/form calendars/index progress_notes/form
      client_advanced_searches/index program_streams/form custom_form_builder
    ].each do |logical|
      expect(File.exist?(ROOT.join("app/assets/javascripts/#{logical}.js"))).to be(true),
        "app/assets/javascripts/#{logical}.js is missing"
    end
  end
end
