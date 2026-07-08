# frozen_string_literal: true
require 'rails_helper'

# Phase 6 (U6) — deletion lifecycle. Client was the only unguarded destroy (full cascade from any
# role with manage-Client); destroys were unaudited; the destroyed client's Mongo history docs
# survived forever. Contract: guard mirrors the Family/Partner/User pattern; every successful
# destroy writes a values-free record_destroyed AccessLog row (a blocked one writes nothing); the
# client's Mongo history is purged post-destroy (the PII-redacted paper_trail destroy version is
# deliberately KEPT as deletion evidence); destroy narrows to admin-only under least-privilege.
RSpec.describe 'Deletion lifecycle', type: :request do
  after(:each) do
    ClientHistory.unscoped.delete_all rescue nil
    AccessLog.unscoped.delete_all rescue nil
  end

  let(:password) { 'SecurePass123!' }
  let!(:admin)   { create(:user, roles: 'admin') }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'clients#destroy guard' do
    it 'blocks destroy while the client has a case and writes NO destroy audit row' do
      client = create(:client)
      family = create(:family)
      create(:case, client: client, family: family, case_type: 'KC')

      sign_in_as(admin)
      expect {
        delete client_path(client)
      }.not_to change(Client, :count)

      expect(response.location).to match(%r{/clients}) # app appends ?locale=en to redirects
      expect(flash[:alert]).to be_present
      expect(AccessLog.unscoped.where(event_type: 'record_destroyed').count).to eq(0)
    end

    it 'blocks destroy while the client has a program enrollment' do
      client  = create(:client)
      program = create(:program_stream)
      create(:client_enrollment, client: client, program_stream: program)

      sign_in_as(admin)
      expect { delete client_path(client) }.not_to change(Client, :count)
      expect(flash[:alert]).to be_present
    end

    it 'destroys an unencumbered client, audits it, and purges the Mongo history' do
      client = create(:client)
      expect(ClientHistory.unscoped.where('object.id' => client.id).count).to be >= 1

      sign_in_as(admin)
      expect { delete client_path(client) }.to change(Client, :count).by(-1)
      expect(flash[:notice]).to be_present

      log = AccessLog.unscoped.where(event_type: 'record_destroyed').last
      expect(log).to be_present
      expect(log.resource_type).to eq('Client')
      expect(log.resource_id).to eq(client.id.to_s)
      expect(log.user_id).to eq(admin.id)

      # Mongo shadow history erased; the paper_trail destroy version is KEPT as evidence.
      expect(ClientHistory.unscoped.where('object.id' => client.id).count).to eq(0)
      expect(PaperTrail::Version.where(item_type: 'Client', item_id: client.id, event: 'destroy')).to exist
    end
  end

  describe 'sibling destroy audit events' do
    it 'audits a family destroy' do
      family = create(:family)
      sign_in_as(admin)
      expect { delete family_path(family) }.to change(Family, :count).by(-1)
      log = AccessLog.unscoped.where(event_type: 'record_destroyed').last
      expect(log.resource_type).to eq('Family')
      expect(log.resource_id).to eq(family.id.to_s)
    end
  end

  describe 'least-privilege destroy narrowing (ability)' do
    let(:worker) { create(:user, roles: 'case worker') }
    let(:client) { create(:client) }
    before { client.users << worker }

    it 'keeps case-worker destroy with the flag OFF (zero behavior change)' do
      expect(Ability.new(worker).can?(:destroy, client)).to be true
    end

    it 'narrows destroy to admin-only under force_least_privilege' do
      expect(Ability.new(worker, force_least_privilege: true).can?(:destroy, client)).to be false
      expect(Ability.new(admin,  force_least_privilege: true).can?(:destroy, client)).to be true
    end

    it 'still lets the narrowed worker read and update their caseload client' do
      narrowed = Ability.new(worker, force_least_privilege: true)
      expect(narrowed.can?(:read, client)).to be true
      expect(narrowed.can?(:update, client)).to be true
    end
  end

  describe 'post-destroy Mongo cleanup resilience' do
    it 'does not fail the destroy when the Mongo purge raises' do
      client = create(:client)
      allow(ClientHistory).to receive(:where).and_raise(Mongo::Error::SocketError.new('down'))
      expect { client.destroy! }.to change(Client, :count).by(-1)
    end
  end
end
