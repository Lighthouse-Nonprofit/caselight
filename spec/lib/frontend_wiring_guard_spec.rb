# frozen_string_literal: true
require 'rails_helper'

# 2026-10-18 frontend pass — two things that silently broke pages:
#   (1) app/assets/javascripts/reports/show.js defined CIF.ReportsShow but was never required from
#       application.js, so the dispatcher (initializer.js) skipped it and report charts never drew.
#   (2) app/views/referrals/index.html.haml used an inline `onchange:` handler, which the enforced
#       nonce CSP drops — the status filter did nothing. The data-auto-submit adapter is the pattern.
# Both are now pinned statically so they cannot regress unnoticed (neither is reachable from the CI
# request specs, which do not execute JS).
RSpec.describe 'Frontend wiring guard' do
  let(:js_root)  { Rails.root.join('app/assets/javascripts') }
  let(:manifest) { js_root.join('application.js').read }

  it 'requires every page module that defines a CIF.<Page> namespace' do
    modules = Dir[js_root.join('**/*.js')].select { |f| File.read(f).match?(/^CIF\.[A-Za-z]+ = /) }
    missing = modules.map { |f| f.sub("#{js_root}/", '').sub(/\.js\z/, '') }
                     .reject { |rel| manifest.match?(/^\/\/= require #{Regexp.escape(rel)}(\.js)?$/) }
    expect(missing).to eq([]), "page modules not required from application.js: #{missing.inspect}"
  end

  it 'has no inline event handlers in views (the enforced CSP drops them)' do
    offenders = Dir[Rails.root.join('app/views/**/*.haml')].select do |f|
      File.read(f).match?(/\bon(change|click|submit|load|input|keyup|keydown|blur|focus)\s*[:=]/)
    end
    expect(offenders).to eq([])
  end

  it 'no longer vendors lodash or DOMPurify' do
    requires = manifest.lines.grep(%r{^//= require})
    expect(requires.grep(/lodash|purify/i)).to eq([])
    expect(Rails.root.join('vendor/assets/javascripts/lodash')).not_to exist
    expect(Rails.root.join('vendor/assets/javascripts/purify.min.js')).not_to exist
  end
end
