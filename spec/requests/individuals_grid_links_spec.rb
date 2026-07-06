# frozen_string_literal: true
require 'rails_helper'

# Donor request (SLO4HOME): on the individuals LIMITED GRID (admin / strategic overviewer),
#   1. the program-stream chips link to the program stream, and
#   2. the "ID" column is replaced by the Case Manager, linked to their user record.
RSpec.describe 'Individuals limited grid links (admin)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:manager)  { create(:user, roles: 'manager', first_name: 'Casey', last_name: 'Manager', password: password, password_confirmation: password) }
  let(:program)  { create(:program_stream, name: 'Housing Support') }
  let!(:client)  { create(:client, given_name: 'Linky', family_name: 'McGrid') }

  before do
    create(:client_enrollment, client: client, program_stream: program, status: 'Active')
    client.users << manager
    post user_session_path, params: { user: { email: admin.email, password: password } }
  end

  it 'links program-stream chips to the stream and shows the case manager linked to their record' do
    get clients_path
    expect(response).to have_http_status(:ok)
    body = response.body

    # It is the limited grid (admin).
    expect(body).to match(/record-grid__table/)

    # (1) program-stream chip links to the stream.
    expect(body).to include(program_stream_path(program))
    expect(body).to include('Housing Support')

    # (2) case manager shown + linked to the user record (in place of the old #slug ID column).
    expect(body).to include(user_path(manager))
    expect(body).to include('Casey Manager')

    # The ID/slug is no longer a column header.
    expect(body).not_to match(/scope=["']col["'][^>]*>\s*ID\s*</)
  end
end
