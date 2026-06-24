require 'rails_helper'

# Tenant routing must accept *.localhost dev hosts (a browser secure context for local WebAuthn
# testing) while leaving real-domain (lvh.me / prod nip.io) routing untouched. The base Apartment
# Subdomain elevator uses PublicSuffix, which does not recognise the `.localhost` TLD.
RSpec.describe Apartment::Elevators::SubdomainWithLocalhost do
  subject(:elevator) { described_class.new(->(_env) {}) }

  def tenant_for(host)
    elevator.parse_tenant_name(double('request', host: host))
  end

  it 'routes a *.localhost host to its first-label tenant' do
    expect(tenant_for('cases.localhost')).to eq('cases')
  end

  it 'does not treat www or a bare localhost as a tenant' do
    expect(tenant_for('www.localhost')).to be_nil
    expect(tenant_for('localhost')).to be_nil
  end

  it 'leaves real-domain subdomain routing unchanged' do
    expect(tenant_for('cases.lvh.me')).to eq('cases')   # 3-label real domain — via PublicSuffix
    expect(tenant_for('lvh.me')).to be_nil               # bare registrable domain — no tenant
  end
end
