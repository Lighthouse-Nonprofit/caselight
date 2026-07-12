# frozen_string_literal: true
require 'rails_helper'

# POAM-017g THE FLIP — REGRESSION GUARD. Bootstrap 3.4.1 + the INSPINIA commercial theme are
# retired; the app runs on vendored Bootstrap 5.3 + the in-house caselight_theme. Mirrors the
# select2/highcharts/tinymce/coffee removal guards. Bans the BS3/INSPINIA gem, asset trees,
# view class vocabulary and JS API surface, and asserts the BS5 replacements are wired.
#
# NB deliberate survivors (NOT banned): the `.ibox` family classnames (restyled on card DNA),
# footable's `data-toggle="true"`, `.label-margin`/`.label-lg` utilities, and the PDF templates
# (`*.pdf.haml` + layouts/pdf_design.html.haml) which stay permanently on Bootstrap 3.3.6.
RSpec.describe 'Bootstrap 3 / INSPINIA removal guard (POAM-017g THE FLIP)' do
  ROOT = Rails.root

  def haml_views
    Dir.glob(ROOT.join('app', 'views', '**', '*.haml')).reject do |f|
      f.end_with?('.pdf.haml') || f.end_with?(File.join('layouts', 'pdf_design.html.haml'))
    end
  end

  def app_js
    Dir.glob(ROOT.join('app', 'assets', 'javascripts', '**', '*.js'))
  end

  # strip `//` line comments so migration-note comments don't trip the JS bans
  def js_code_lines(file)
    File.read(file, encoding: 'UTF-8').lines.map { |l| l.sub(%r{//.*$}, '') }
  end

  # ---- Gem + build config ------------------------------------------------------------------
  it 'has dropped the bootstrap-sass and bootstrap-datepicker-rails gems' do
    # comment-strip the Gemfile so the removal-note comments don't count
    gemfile = File.read(ROOT.join('Gemfile')).lines.map { |l| l.sub(/#.*$/, '') }.join
    expect(gemfile).not_to match(/gem\s+['"]bootstrap-sass['"]/), 'Gemfile still declares bootstrap-sass'
    expect(gemfile).not_to match(/gem\s+['"]bootstrap-datepicker-rails['"]/), 'Gemfile still declares bootstrap-datepicker-rails'
    lock = File.read(ROOT.join('Gemfile.lock')) # lockfiles carry no comments
    expect(lock).not_to match(/\bbootstrap-sass\b/), 'Gemfile.lock still locks bootstrap-sass'
    expect(lock).not_to match(/\bbootstrap-datepicker-rails\b/), 'Gemfile.lock still locks bootstrap-datepicker-rails'
  end

  it 'no longer feeds the bootstrap-sass gem path to dart-sass (keeps the vendor path)' do
    code = File.read(ROOT.join('config/initializers/dartsass.rb')).lines.map { |l| l.sub(/#.*$/, '') }.join
    expect(code).not_to match(/bootstrap-sass/), 'dartsass.rb still references the bootstrap-sass gem path'
    expect(code).to include('--load-path=vendor/assets/stylesheets')
  end

  # ---- BS5 replacements present ------------------------------------------------------------
  it 'has the vendored Bootstrap 5 + plugin assets wired' do
    %w[
      vendor/assets/stylesheets/bootstrap5/bootstrap.scss
      vendor/assets/javascripts/bootstrap.bundle.min.js
      vendor/assets/javascripts/vanillajs-datepicker/datepicker-full.min.js
      vendor/assets/javascripts/bootstrap_file_input5/fileinput.js
      vendor/assets/stylesheets/vanillajs-datepicker-bs5.min.css
      vendor/assets/stylesheets/tom-select.bootstrap5.css
      app/assets/stylesheets/caselight_theme/theme.scss
      app/assets/javascripts/caselight_shell.js
      app/assets/javascripts/shared/date_picker.js
    ].each do |rel|
      expect(File.exist?(ROOT.join(rel))).to be(true), "missing BS5 asset: #{rel}"
    end
  end

  # ---- Deleted BS3 / INSPINIA trees --------------------------------------------------------
  it 'has deleted the INSPINIA + BS3 asset trees' do
    gone = %w[
      app/assets/stylesheets/wrapbootstrap
      app/assets/javascripts/wrapbootstrap
      app/assets/javascripts/bs3_jquery4_data_shim.js
      app/assets/javascripts/datepicker.js
      app/assets/stylesheets/iCheck
      app/assets/stylesheets/tom_select_bs3.scss
      vendor/assets/javascripts/iCheck
      vendor/assets/stylesheets/iCheck
      vendor/assets/javascripts/slimscroll
      vendor/assets/stylesheets/animate
      vendor/assets/stylesheets/bootstrap-datepicker.css
      vendor/assets/javascripts/bootstrap-datepicker
      vendor/assets/javascripts/bootstrap_file_input
      vendor/assets/stylesheets/bootstrap_file_input
      public/fonts/bootstrap
    ]
    offenders = gone.select { |rel| File.exist?(ROOT.join(rel)) }
    expect(offenders).to be_empty, "these should have been deleted at the flip: #{offenders.join(', ')}"
  end

  # ---- View class vocabulary bans (PDF templates exempt) -----------------------------------
  {
    'col-xs-*'            => /\bcol-xs-/,
    'glyphicon'           => /glyphicon/,
    'panel-heading/body'  => /panel-heading|panel-body/,
    'btn-default'         => /\bbtn-default\b/,
    'input-group-addon'   => /input-group-addon/,
    'help-block'          => /\bhelp-block\b/,
    'i-checks'            => /\bi-checks\b/,
    'pull-left/right'     => /\bpull-(left|right)\b/,
    'label label-*'       => /\blabel label-/,
    # bootstrap-VALUED data-toggle (footable's data-toggle="true" survives)
    'bootstrap data-toggle' => /["']data-toggle["']\s*(?:=>|:)\s*["'](?:modal|dropdown|collapse|tab|pill|popover|tooltip|buttons?)["']/,
  }.each do |label, pattern|
    it "has no `#{label}` left in the HAML views" do
      offenders = haml_views.select { |f| File.read(f, encoding: 'UTF-8').match?(pattern) }
      expect(offenders).to be_empty,
        "BS3 `#{label}` found in views (flip should have removed it): #{offenders.map { |f| f.sub(ROOT.to_s + '/', '') }.join(', ')}"
    end
  end

  # ---- JS API bans (comment-stripped; shell + adapters allowlisted) ------------------------
  JS_ALLOWLIST = %w[caselight_shell.js shared/date_picker.js].freeze

  {
    'bootstrap-sprockets require' => /require\s+bootstrap-sprockets/,
    '.iCheck('                    => /\.iCheck\(/,
    'jQuery .modal('              => /\.modal\(/,
    'jQuery .tab('                => /\.tab\(/,
  }.each do |label, pattern|
    it "has no `#{label}` in the app JavaScript" do
      offenders = app_js.reject { |f| JS_ALLOWLIST.any? { |a| f.end_with?(a) } }
                        .select { |f| js_code_lines(f).any? { |l| l.match?(pattern) } }
      expect(offenders).to be_empty,
        "BS3 JS `#{label}` found (use bootstrap.Modal/Tab or native controls): #{offenders.map { |f| f.sub(ROOT.to_s + '/', '') }.join(', ')}"
    end
  end

  it 'application.js requires the BS5 bundle + shell + datepicker adapter, not the BS3 assets' do
    m = File.read(ROOT.join('app/assets/javascripts/application.js'))
    expect(m).to match(%r{^//=\s*require\s+bootstrap\.bundle\.min$})
    expect(m).to match(%r{^//=\s*require\s+caselight_shell$})
    expect(m).to match(%r{^//=\s*require\s+shared/date_picker$})
    expect(m).not_to match(%r{^//=\s*require\s+bootstrap-sprockets$})
    expect(m).not_to match(%r{^//=\s*require\s+iCheck/})
    expect(m).not_to match(%r{^//=\s*require\s+wrapbootstrap/})
    expect(m).not_to match(%r{^//=\s*require\s+slimscroll/})
    expect(m).not_to match(%r{^//=\s*require\s+bs3_jquery4_data_shim$})
    expect(m).not_to match(%r{^//=\s*require\s+bootstrap-datepicker/})
  end

  it 'application.scss imports the caselight theme, not the INSPINIA/BS3 stylesheets' do
    s = File.read(ROOT.join('app/assets/stylesheets/application.scss'))
    expect(s).to include("@import 'caselight_theme/theme';")
    expect(s).not_to match(/@import 'wrapbootstrap/)
    expect(s).not_to match(/@import 'iCheck/)
    expect(s).not_to match(%r{@import 'animate/animate'})
    expect(s).not_to match(/@import 'bootstrap-datepicker'/)
    expect(s).not_to match(/@import 'tom_select_bs3'/)
  end

  # ---- Compiled CSS discriminator (skips when the bundle has not been built) ---------------
  it 'compiles to a Bootstrap-5 bundle (--bs- vars present; glyphicons/INSPINIA skins gone)' do
    built = ROOT.join('app/assets/builds/application.css')
    skip 'application.css not built in this environment' unless File.exist?(built)
    css = File.read(built, encoding: 'UTF-8')
    expect(css).to include('--bs-'), 'no Bootstrap-5 CSS custom properties in the compiled bundle'
    expect(css).to include('.ibox'), 'the .ibox theme layer is missing from the compiled bundle'
    expect(css).not_to include('Glyphicons Halflings'), 'BS3 glyphicon font still in the bundle'
    expect(css).not_to include('md-skin'), 'INSPINIA .md-skin still in the bundle'
  end
end
