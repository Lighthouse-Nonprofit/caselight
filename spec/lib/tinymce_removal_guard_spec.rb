# frozen_string_literal: true
require 'rails_helper'

# POAM-017a REGRESSION GUARD — TinyMCE 4 (EOL 2022) is out; Trix 2 is the rich-text editor.
#
# Mirrors spec/lib/highcharts_removal_guard_spec.rb: assert the retired library cannot
# quietly return, and that its replacement stays wired. Deliberately guards FUNCTIONAL
# tokens (gem declaration, sprockets require, init call, editor CSS-class hook) rather
# than the word "TinyMCE" — comments and compliance docs legitimately reference the
# retired editor by name (e.g. rich_text_helper.rb documents that legacy content was
# TinyMCE-authored).
RSpec.describe 'TinyMCE removal guard (POAM-017a)' do
  ROOT = Rails.root

  def files_under(*relative_dirs, exts: nil)
    relative_dirs.flat_map do |dir|
      Dir.glob(ROOT.join(dir, '**', '*')).select do |f|
        File.file?(f) && (exts.nil? || exts.include?(File.extname(f)))
      end
    end.sort
  end

  it 'has no tinymce-rails gem in the Gemfile or lockfile' do
    expect(File.read(ROOT.join('Gemfile'))).not_to match(/^\s*gem\s+['"]tinymce-rails['"]/)
    expect(File.read(ROOT.join('Gemfile.lock'))).not_to include('tinymce-rails')
  end

  it 'has no sprockets require of a tinymce asset' do
    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).not_to match(%r{^//=\s*require\s+tinymce}i)
  end

  it 'has no tinymce init call in any JS/coffee source' do
    offenders = files_under('app/assets/javascripts', 'vendor/assets/javascripts',
                            exts: %w[.js .coffee]).select do |f|
      File.read(f, encoding: 'UTF-8').match?(/tinymce\.init|tinyMCE\.init/)
    end
    expect(offenders).to be_empty,
      "tinymce.init found in: #{offenders.join(', ')} — the editor is Trix now (POAM-017a)."
  end

  it 'has no tinymce-classed editor hook left in any view' do
    offenders = files_under('app/views', exts: %w[.haml .erb]).select do |f|
      File.read(f, encoding: 'UTF-8').match?(/['".]tinymce\b/)
    end
    expect(offenders).to be_empty,
      "a 'tinymce' class/selector hook remains in: #{offenders.join(', ')}"
  end

  it 'keeps the Trix replacement wired (vendored assets + requires + import)' do
    expect(File.exist?(ROOT.join('vendor/assets/javascripts/trix.js'))).to be(true),
      'vendor/assets/javascripts/trix.js is missing'
    expect(File.exist?(ROOT.join('vendor/assets/stylesheets/trix.scss'))).to be(true),
      'vendor/assets/stylesheets/trix.scss is missing'

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+trix$}), 'application.js must //= require trix'
    expect(manifest).to match(%r{^//=\s*require\s+rich_text$}),
      'application.js must //= require rich_text (the app-wide Trix config)'

    stylesheet = File.read(ROOT.join('app/assets/stylesheets/application.scss'))
    expect(stylesheet).to include("@import 'trix';")
    expect(stylesheet).to include("@import 'rich_text';")

    # Attachments must stay disabled: the sanitizer denies <img>, so the editor must not
    # offer an upload affordance (rich_text.js cancels trix-file-accept).
    expect(File.read(ROOT.join('app/assets/javascripts/rich_text.js')))
      .to include('trix-file-accept')
  end
end
