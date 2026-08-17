# frozen_string_literal: true
require 'rails_helper'

# Pre-migration PR 4:
#   (1) Referrals OUT — a per-client outbound-referral record (business referred to for work,
#       housing, legal, …), distinct from ReferralSource (referrals IN). Per-client hub section
#       + an org-wide manage list scoped to the viewer's accessible clients.
#   (2) Donor management — richer fields (contact, type/status, giving summary).
RSpec.describe 'Referrals (out) + Donor management', type: :request do
  include Devise::Test::IntegrationHelpers

  describe 'Referrals — per-client hub section' do
    let!(:admin) { create(:user, roles: 'admin') }
    let(:client) { create(:client) }
    before { sign_in admin }

    it 'opens the client referrals tab' do
      get client_referrals_path(client)
      expect(response).to have_http_status(:ok)
    end

    it 'records a referral out and encrypts the narrative at rest' do
      expect do
        post client_referrals_path(client), params: { referral: {
          organization_name: 'Central Coast Staffing',
          referral_type: 'Employment',
          contact_name: 'Jordan Lee',
          referred_on: Date.current.to_s,
          status: 'Pending',
          reason: 'Client seeking warehouse work.'
        } }
      end.to change { client.referrals.count }.by(1)

      referral = client.referrals.last
      expect(referral.organization_name).to eq('Central Coast Staffing')
      expect(referral.reason).to eq('Client seeking warehouse work.')
      # non-deterministic encryption → ciphertext on disk differs from plaintext
      raw = Referral.connection.select_value("SELECT reason FROM referrals WHERE id = #{referral.id}")
      expect(raw).not_to eq('Client seeking warehouse work.')
    end

    it 'defaults the referring staff to the current user when left blank' do
      post client_referrals_path(client), params: { referral: {
        organization_name: 'Acme Legal Aid', status: 'Pending'
      } }
      expect(client.referrals.last.user).to eq(admin)
    end

    it 'updates a referral status' do
      referral = client.referrals.create!(organization_name: 'Acme', status: 'Pending')
      patch client_referral_path(client, referral), params: { referral: { status: 'Completed' } }
      expect(referral.reload.status).to eq('Completed')
    end
  end

  describe 'Referrals — org-wide manage list is caseload-scoped' do
    let!(:worker)     { create(:user, roles: 'case worker') }
    let(:mine)        { create(:client) }
    let(:not_mine)    { create(:client) }
    before do
      mine.users = [worker]
      mine.referrals.create!(organization_name: 'MyCaseload Employer', status: 'Pending')
      not_mine.referrals.create!(organization_name: 'OtherWorker Employer', status: 'Pending')
      sign_in worker
    end

    it 'shows only referrals on the worker’s accessible clients' do
      get referrals_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('MyCaseload Employer')
      expect(response.body).not_to include('OtherWorker Employer')
    end
  end

  describe 'Donor — rich fields' do
    let!(:admin) { create(:user, roles: 'admin') }
    before { sign_in admin }

    it 'creates a donor with the new management fields' do
      expect do
        post donors_path, params: { donor: {
          name: 'Coastal Community Foundation', donor_type: 'Foundation', status: 'Active',
          contact_name: 'Pat Rivera', email: 'grants@ccf.example.org', phone: '805-555-0100',
          total_giving: '25000.00', last_gift_amount: '5000.00', last_gift_on: Date.current.to_s
        } }
      end.to change { Donor.count }.by(1)

      donor = Donor.order(:id).last
      expect(donor.donor_type).to eq('Foundation')
      expect(donor.status).to eq('Active')
      expect(donor.total_giving).to eq(25_000)
      expect(donor.contact_name).to eq('Pat Rivera')
    end

    it 'rejects a malformed contact email' do
      post donors_path, params: { donor: { name: 'Bad Email Donor', email: 'not-an-email' } }
      expect(Donor.find_by(name: 'Bad Email Donor')).to be_nil
    end
  end
end
