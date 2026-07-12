# frozen_string_literal: true
require 'rails_helper'

# POAM-017f GUARD (formBuilder half, PR 12B) — the 2016-vintage formBuilder 1.24.2 is upgraded
# to the maintained 3.x line (vendored dist), and the never-called formRender is deleted
# outright (all data-entry forms render server-side via app/views/shared/fields +
# program_streams/fields). Mirrors the other removal/upgrade guards in this directory.
RSpec.describe 'formBuilder upgrade guard (POAM-017f)' do
  ROOT = Rails.root

  it 'has no formRender asset, require, or API usage' do
    offenders = Dir.glob(ROOT.join('{app,vendor}', 'assets', '**', '*form-render*'))
    expect(offenders).to be_empty, "formRender assets found: #{offenders.join(', ')}"

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).not_to match(%r{^//=\s*require\s+form-render}), 'application.js still requires form-render'

    api_usage = Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js')).select do |f|
      next false if File.basename(f) == 'form-builder.min.js'
      File.read(f, encoding: 'UTF-8').lines.any? { |l| l.sub(%r{//.*$}, '').match?(/formRender\(/) }
    end
    expect(api_usage).to be_empty, "formRender API usage found: #{api_usage.join(', ')}"
  end

  it 'ships formBuilder 3.x vendored, required, and 1.x fully retired' do
    old_copy = ROOT.join('app/assets/javascripts/form-builder.min.js')
    expect(File.exist?(old_copy)).to be(false), 'the 1.24.2 copy under app/assets must stay deleted'

    vendored = ROOT.join('vendor/assets/javascripts/form-builder.min.js')
    expect(File.exist?(vendored)).to be(true)
    dist = File.read(vendored, encoding: 'UTF-8')

    # 3.x-distinctive tokens present; the 1.x global absent anywhere in shipped JS
    expect(dist).to include('fbInstance')
    expect(dist).to include('formbuilder-icon')
    expect(dist).not_to include('formBuilderHelpersFn')

    manifest = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(manifest).to match(%r{^//=\s*require\s+form-builder\.min\.js$})

    # 3.x injects its styles at runtime — the 1.x vendored css must stay deleted
    expect(Dir.exist?(ROOT.join('vendor/assets/stylesheets/formBuilder'))).to be(false)
    stylesheet = File.read(ROOT.join('app/assets/stylesheets/application.scss'))
    expect(stylesheet).not_to match(%r{@import ['"]formBuilder/})
  end

  it 'keeps the vendored dist eval-free (the CSP gate as a permanent assertion)' do
    dist = File.read(ROOT.join('vendor/assets/javascripts/form-builder.min.js'), encoding: 'UTF-8')
    expect(dist).not_to include('eval(')
    expect(dist).not_to include('new Function')
    # the single Function( occurrence is lodash's unreachable global-this fallback
    # (Function(`return this`)()), identical to the one in our standalone vendored lodash —
    # never invoked in browsers (self.Object === Object short-circuits it)
    occurrences = dist.scan(/Function\(/).size
    expect(occurrences).to be <= 1
    if occurrences == 1
      expect(dist).to match(/Function\(`return this`\)\(\)/),
        'an unexpected Function( call appeared — audit it before shipping'
    end
  end

  it 'strips the CDN-loading tinymce/quill textarea subtypes from the builder UI' do
    # formBuilder 3.x's tinymce/quill textarea subtypes inject the editor FROM cdnjs at
    # runtime when window.tinymce/Quill is absent — an unpinned third-party script that
    # would reintroduce the retired TinyMCE (POAM-017a) and violate the enforced CSP.
    # The textarea typeUserEvents handler must keep removing them from .fld-subtype.
    handler = File.read(ROOT.join('app/assets/javascripts/custom_form_builder.js'))
    expect(handler).to include('option:contains(tinymce)'),
      'eventTextAreaOption must strip the tinymce subtype (CDN script injection path)'
    expect(handler).to include('option:contains(quill)'),
      'eventTextAreaOption must strip the quill subtype (CDN script injection path)'
  end

  it 'hosts the mi18n language file at the absolute location the shared options point at' do
    # mi18n always fetches <location><locale>.lang at init (addLanguage never marks the
    # locale loaded) — without this file every builder page logs a 404
    expect(File.exist?(ROOT.join('public/fb-lang/en-US.lang'))).to be(true)
    shared_options = File.read(ROOT.join('app/assets/javascripts/custom_form_builder.js'))
    expect(shared_options).to include("location: '/fb-lang/'")
    expect(shared_options).to include('builderOptions')
  end
end
