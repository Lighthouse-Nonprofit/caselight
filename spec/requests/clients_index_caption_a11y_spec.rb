# frozen_string_literal: true
require 'rails_helper'

# Surface B: the clients hand-built table bypasses datagrid/_table, so its caption is added at the
# call site. This request spec (CI-covered spec/requests) drives GET /clients as an admin and
# asserts the sr-only <caption> ('Clients') renders before <thead> AND that the <th> get
# scope=col from the shared _head partial. Replaces the fragile inline-HAML view spec the author
# proposed (render inline: ... type: :haml is unreliable in rspec-rails). Login + tenant setup
# mirror spec/requests/custom_field_property_index_render_spec.rb.
RSpec.describe 'clients/index caption (surface B)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'renders an sr-only caption before the thead and scope=col headers on the clients grid' do
    get clients_path
    expect(response).to have_http_status(:ok)
    body = response.body
    expect(body).to match(/<caption[^>]*class=["'][^"']*sr-only/)
    expect(body).to include('Clients')
    expect(body.index('<caption')).to be < body.index('<thead')
    expect(body).to match(/scope=["']col["']/)
  end
end