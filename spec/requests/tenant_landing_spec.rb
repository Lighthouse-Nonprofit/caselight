# frozen_string_literal: true
require 'rails_helper'

# A host that names a tenant must land on THAT org, never on a picker.
#
# Organization is an Apartment *excluded* model, so `root 'organizations#index'` reads the public
# schema whatever tenant the elevator selected — which meant every org on a box saw every other
# org's name on its own landing page. (Found in production 2026-08-04, where a redeploy without
# TENANT_SHORT had created a stray second tenant and the owner saw two entries at their own
# hostname.) The picker still exists for a host that resolves NO tenant, which is the only place
# choosing between organizations makes sense.
#
# Host semantics under test: the default request host is www.example.com, whose 'www' label is an
# excluded subdomain (config/initializers/apartment/subdomain_exclusions.rb) -> no tenant. The
# suite's real tenant is 'app' (spec_helper before(:suite)), so 'app.lvh.me' is a host that
# resolves a tenant AND has a schema for the elevator to switch into.
RSpec.describe 'tenant landing', type: :request do
  let!(:other_org) { create(:organization, full_name: 'Some Other Nonprofit', short_name: 'otherorg') }
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'a host that names a tenant' do
    before { host! 'app.lvh.me' }

    it 'sends a signed-out visitor to that tenant\'s sign-in, not the org list' do
      get root_path
      # (redirects carry ?locale=en, so match the path, not the whole URL)
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/users/sign_in')
    end

    it 'never leaks another organization\'s name to it' do
      get root_path
      follow_redirect!
      expect(response.body).not_to include('Some Other Nonprofit')
    end

    it 'still sends a signed-in user straight to their dashboard' do
      sign_in_as(create(:user, :admin, password: password, password_confirmation: password))
      get root_path
      expect(response).to have_http_status(:redirect)
      expect(response.location).to include('/dashboards')
    end
  end

  describe 'a host that names no tenant (the bare domain)' do
    it 'keeps the picker, listing every organization' do
      get root_path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Some Other Nonprofit')
    end
  end

  describe 'sign-in branding' do
    before { host! 'app.lvh.me' }

    let(:org) { Organization.find_by(short_name: 'app') }

    after { org.remove_logo! }

    it "shows the tenant's own logo once one is attached" do
      org.logo = File.open(Rails.root.join('spec/supports/download_image.png'))
      org.save!

      get new_user_session_path
      expect(response.body).to include('/uploads/organization/logo/')
      expect(response.body).not_to include('brand/caselight-logo')
    end

    it 'falls back to the product logo for a tenant with none' do
      get new_user_session_path
      expect(response.body).to include('brand/caselight-logo')
      expect(response.body).not_to include('/uploads/organization/logo/')
    end
  end
end
