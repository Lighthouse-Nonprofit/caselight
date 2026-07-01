# frozen_string_literal: true
require 'rails_helper'

# Units 13-15 (Section 508 / WCAG 2.1 AA) -- SURFACE C: image_tag alt text.
# CI runs a js-EXCLUDING subset (spec/requests + spec/helpers), so a11y attributes must be
# assertable by rendering through a real controller and inspecting response.body.
#
# ANCHOR: organizations#index is the public tenant landing (root 'organizations#index',
# skip_authorization_check, no login). It renders each org.logo tile INSIDE the link_to the org
# dashboard. The fix adds alt naming the org. image_tag emits alt with DOUBLE quotes (Rails tag
# helper), so include('alt="..."') is correct here.
RSpec.describe 'Surface C: image alt text', type: :request do
  describe 'organizations#index (public tenant landing)' do
    let!(:org) { create(:organization, full_name: 'Acme Refugee Services', short_name: 'acme') }

    before { get root_path }

    it 'renders the org logo tile with a descriptive alt naming the organization' do
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('alt="Acme Refugee Services"')
    end

    it 'never emits the alt value unescaped (XSS-safe interpolation)' do
      create(:organization, full_name: '<script>x</script>Org', short_name: 'xssorg')
      get root_path
      expect(response.body).not_to include('<script>x</script>Org')
      expect(response.body).to include('&lt;script&gt;')
    end
  end
end