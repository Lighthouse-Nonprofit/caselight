# frozen_string_literal: true
require 'rails_helper'

# UNIT 11 — proprietary-charting-library removal REGRESSION GUARD.
#
# Unit 11 replaced the proprietary charting library (vendor/assets/javascripts/highcharts.js,
# v5.0.6) with Chart.js v4.4.7 (MIT, vendored UMD at vendor/assets/javascripts/chart.umd.js).
# The removed library is license-encumbered; this AGPL project must carry ZERO such deps.
# CIF.ReportCreator (app/assets/javascripts/report_creator.coffee) now renders lineChart/
# pieChart/donutChart onto <canvas> elements via Chart.js.
#
# This is a REGRESSION GUARD, not a fixer: it walks the source tree, reads file text, and
# asserts the banned token is absent (any reintroduction — a re-vendored lib, a `.highcharts()`
# call, a `.highcharts-*` CSS rule, a `//= require highcharts` directive — is caught). It needs
# no DB and is fast/deterministic (spec/lib is in the CI rspec subset). Only THIS spec file is
# allowlisted, because it necessarily contains the banned token in its own prose.
RSpec.describe 'Proprietary charting-library removal regression guard (Unit 11)' do
  ROOTS = %w[app config lib vendor/assets].freeze

  # This spec is the ONLY file permitted to contain the banned token (it documents the ban).
  SELF_RELPATH = 'spec/lib/highcharts_removal_guard_spec.rb'

  # Text source files we police under ROOTS. Skip binary-ish/asset blobs by extension allowlist
  # — we care about hand-authored source (js/coffee/scss/css/haml/erb/rb/yml/json).
  POLICED_EXTS = %w[.js .coffee .scss .css .sass .haml .erb .rb .yml .yaml .json].freeze

  # Repo-relative, forward-slashed path for an absolute file under Rails.root.
  def relpath(file)
    Pathname.new(file).relative_path_from(Rails.root).to_s.tr('\\\\', '/')
  end

  def policed_files
    ROOTS.flat_map do |root|
      Dir.glob(Rails.root.join(root, '**', '*')).select do |f|
        File.file?(f) && POLICED_EXTS.include?(File.extname(f))
      end
    end.uniq.sort
  end

  it 'has ZERO "highchart" references (case-insensitive) under app/, config/, lib/, vendor/assets' do
    offenders = []
    policed_files.each do |file|
      rel = relpath(file)
      next if rel == SELF_RELPATH
      File.read(file, encoding: 'UTF-8').each_line.each_with_index do |line, i|
        next unless line =~ /highchart/i
        offenders << "#{rel}:#{i + 1}: #{line.strip}"
      end
    rescue ArgumentError
      next # non-UTF-8 blob that slipped past the extension allowlist — nothing to scan
    end
    expect(offenders).to be_empty, <<~MSG
      Found a reference to the removed proprietary charting library. It was replaced in Unit 11
      by Chart.js v4 (MIT) because this AGPL project carries ZERO license-encumbered deps.
      Render charts through CIF.ReportCreator (Chart.js) instead — do not reintroduce the old lib
      (no re-vendored file, no `.highcharts()` call, no `.highcharts-*` CSS, no `//= require`).
      Offenders:
      #{offenders.join("\n")}
    MSG
  end

  it 'no longer vendors the proprietary highcharts.js file' do
    expect(File.exist?(Rails.root.join('vendor/assets/javascripts/highcharts.js')))
      .to be(false), 'vendor/assets/javascripts/highcharts.js must be deleted (Unit 11).'
  end

  it 'vendors the MIT Chart.js UMD build and requires it from application.js' do
    expect(File.exist?(Rails.root.join('vendor/assets/javascripts/chart.umd.js')))
      .to be(true), 'vendor/assets/javascripts/chart.umd.js (Chart.js v4 UMD) must be present.'
    app_js = File.read(Rails.root.join('app/assets/javascripts/application.js'), encoding: 'UTF-8')
    expect(app_js).to match(%r{^\s*//=\s*require\s+chart\.umd\s*$}),
      'application.js must `//= require chart.umd` (the Chart.js UMD asset).'
  end
end
