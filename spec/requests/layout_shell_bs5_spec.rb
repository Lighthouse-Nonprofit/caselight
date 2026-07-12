# frozen_string_literal: true
require 'rails_helper'

# POAM-017g THE FLIP — the authenticated shell renders on Bootstrap 5. Complements the static
# bootstrap3_removal_guard_spec with a REAL rendered-output check: the INSPINIA-era chrome
# classnames survive (restyled), interactive triggers use data-bs-* (not BS3 data-*), and modal
# closes use data-bs-dismiss. /agencies is a representative index (shell + add/edit modals; its
# add-modal `_form` partial always renders the dismiss button, independent of seed data).
RSpec.describe 'BS5 layout shell (POAM-017g)', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }
  before { sign_in admin }

  let(:body) do
    get '/agencies'
    expect(response).to have_http_status(:ok)
    response.body
  end

  it 'renders the themed shell chrome with a data-bs-toggle trigger' do
    expect(body).to include('navbar-static-side')      # sidebar shell (classname kept, restyled)
    expect(body).to match(/id=["']page-wrapper["']/)    # content shell
    expect(body).to match(/data-bs-toggle=["'](?:modal|dropdown|collapse|tab)["']/)
  end

  it 'emits no bootstrap-valued BS3 data-toggle attributes (only data-bs-toggle)' do
    # footable's data-toggle="true" is allowed; the bootstrap component values are not
    expect(body).not_to match(/\bdata-toggle=["'](?:modal|dropdown|collapse|tab|pill|popover|tooltip)["']/)
  end

  it 'dismisses modals/alerts via data-bs-dismiss, never the BS3 data-dismiss' do
    expect(body).to match(/data-bs-dismiss=["'](?:modal|alert)["']/) # the modal close buttons
    expect(body).not_to match(/\bdata-dismiss=["'](?:modal|alert)["']/)
  end
end
