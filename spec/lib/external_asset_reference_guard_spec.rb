# frozen_string_literal: true
require 'rails_helper'

# POAM-017f / 12C-1 GUARD — the app self-hosts everything: Google Fonts became
# public/fonts/open-sans (the @import url() lines used to load at runtime from
# fonts.googleapis.com), the 404/500 pages dropped their maxcdn bootstrap <link>, and the
# infinite-scroll spinner left imgur. The enforced CSP (12C) pins every fetch directive to
# 'self', so ANY external asset reference that creeps back in would be a broken resource.
# POAM-017g P3 removed the last exemption: layouts/pdf_design now INLINES its self-hosted
# BS 3.3.6 print stylesheet (public/pdf/), so even the wkhtmltopdf render is network-free.
RSpec.describe 'external asset reference guard (POAM-017f)' do
  ROOT = Rails.root
  EXTERNAL = /fonts\.googleapis|fonts\.gstatic|maxcdn\.bootstrapcdn|cdnjs\.cloudflare|imgur\.com/

  it 'has no external asset references in stylesheets' do
    offenders = Dir.glob(ROOT.join('app', 'assets', 'stylesheets', '**', '*.{scss,css}')).select do |f|
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(EXTERNAL) }
    end
    expect(offenders).to be_empty, "external asset references found: #{offenders.join(', ')}"
  end

  it 'has no external asset references in app javascripts' do
    offenders = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      # the vendored formBuilder dist carries a cdnjs loader for OPTIONAL editor subtypes
      # that are stripped from the UI (formbuilder_upgrade_guard_spec asserts the strip)
      next false if File.basename(f) == 'form-builder.min.js'

      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(EXTERNAL) }
    end
    expect(offenders).to be_empty, "external asset references found: #{offenders.join(', ')}"
  end

  it 'has no external asset references in ANY view (pdf_design self-hosts since P3)' do
    offenders = Dir.glob(ROOT.join('app', 'views', '**', '*.haml')).select do |f|
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(/-#.*$/, '').match?(EXTERNAL) }
    end
    expect(offenders).to be_empty, "external asset references found: #{offenders.join(', ')}"
  end

  it 'ships the inlined BS 3.3.6 print stylesheet the pdf layout reads' do
    css = ROOT.join('public/pdf/bootstrap-3.3.6.min.css')
    expect(File.exist?(css)).to be(true), 'missing public/pdf/bootstrap-3.3.6.min.css'
    expect(File.size(css)).to be > 100_000
    expect(File.read(ROOT.join('app/views/layouts/pdf_design.html.haml')))
      .to include("Rails.root.join('public/pdf/bootstrap-3.3.6.min.css').read")
  end

  it 'ships the self-hosted Open Sans faces the stylesheet points at' do
    %w[300 400 600 700].each do |weight|
      expect(File.exist?(ROOT.join("public/fonts/open-sans/open-sans-#{weight}.woff2"))).to be(true),
        "missing public/fonts/open-sans/open-sans-#{weight}.woff2"
    end
    # POAM-017g flip: the @font-face blocks moved from the deleted wrapbootstrap tree into the
    # in-house theme (caselight_theme/_root.scss, imported by caselight_theme/theme.scss).
    faces = File.read(ROOT.join('app/assets/stylesheets/caselight_theme/_root.scss'))
    expect(faces.scan(/@font-face/).size).to eq(4)
    expect(File.read(ROOT.join('app/assets/stylesheets/caselight_theme/theme.scss')))
      .to include("@import 'root';")
  end
end
