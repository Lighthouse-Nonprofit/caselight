# frozen_string_literal: true
require 'rails_helper'

# POAM-017d REGRESSION GUARD — FullCalendar 3.9 + moment.js are out; the calendar runs on
# a vendored FullCalendar 6 standard bundle (jQuery/moment-free). Mirrors the other
# removal guards.
RSpec.describe 'fullcalendar 3 / moment removal guard (POAM-017d)' do
  ROOT = Rails.root

  it 'has no fullcalendar-rails or momentjs-rails gems in the Gemfile or lockfile' do
    gemfile = File.read(ROOT.join('Gemfile'))
    expect(gemfile).not_to match(/^\s*gem\s+['"]fullcalendar-rails['"]/)
    expect(gemfile).not_to match(/^\s*gem\s+['"]momentjs-rails['"]/)
    lock = File.read(ROOT.join('Gemfile.lock'))
    expect(lock).not_to include('fullcalendar-rails')
    expect(lock).not_to include('momentjs-rails')
  end

  it 'has no moment usage in app javascripts' do
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(/\bmoment(\.parseZone)?\s*\(/) }
    end
    expect(offenders).to be_empty, "moment usage found: #{offenders.join(', ')}"
  end

  it 'has no FullCalendar v3 jQuery-plugin API usage' do
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      File.read(f, encoding: 'UTF-8').match?(/\.fullCalendar\(/)
    end
    expect(offenders).to be_empty,
      "FC3 jQuery-plugin API found (use the FC6 Calendar instance): #{offenders.join(', ')}"
  end

  it 'keeps the FullCalendar 6 replacement wired' do
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/fullcalendar.js'))).to be(true)
    expect(File.read(ROOT.join('vendor/assets/javascripts/fullcalendar.js'), encoding: 'UTF-8'))
      .to match(/FullCalendar Standard Bundle v6/)
    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+fullcalendar$})
    expect(manifest).not_to match(%r{^//=\s*require\s+moment$})
    # the FC3 stylesheet import is gone (FC6 injects styles at runtime)
    expect(File.read(ROOT.join('app/assets/stylesheets/application.scss')))
      .not_to match(/@import ['"]fullcalendar['"]/)
  end
end
