# frozen_string_literal: true
require 'rails_helper'

# bootstrap.sh used to open with TENANT_SHORT="${TENANT_SHORT:-cases}", so a redeploy that forgot
# to re-export the box's tenant silently created a SECOND organization + PG schema next to the real
# one. That happened on the SLO for HOME production box on 2026-08-04 (the owner saw two tenants on
# their landing page). The script is not covered by any other spec, so pin the three properties that
# make the mistake impossible rather than merely unlikely.
RSpec.describe 'bootstrap.sh tenant handling' do
  let(:script) { File.read(Rails.root.join('bootstrap.sh')) }

  it 'never inlines the demo default into the tenant resolution' do
    expect(script).not_to match(/\$\{TENANT_SHORT:-cases\}/),
      'the literal default must not be what an unset TENANT_SHORT falls back to directly'
    expect(script).to include("TENANT_SHORT_DEFAULT='cases'")
    expect(script).to include('TENANT_SHORT_ARG=')
  end

  it 'prefers an explicit env var, then the value pinned in .env, then the default' do
    expect(script).to match(/TENANT_SHORT="\$\{TENANT_SHORT_ARG:-\$\(env_pin TENANT_SHORT\)\}"/)
    expect(script).to match(/TENANT_SHORT="\$\{TENANT_SHORT:-\$TENANT_SHORT_DEFAULT\}"/)
  end

  it 'refuses to create an unnamed tenant on a box that already has organizations' do
    expect(script).to match(/NOT creating/)
    expect(script).to match(/Organization\.exists\?/)
  end

  it 'pins the resolved tenant into .env so the next deploy needs no environment' do
    expect(script).to match(/grep -q '\^TENANT_SHORT=' \.env \|\|/)
    expect(script).to match(/grep -q '\^TENANT_FULL='\s+\.env \|\|/)
  end
end
