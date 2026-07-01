# frozen_string_literal: true
require 'rails_helper'

# Card-grid redesign (surface B): the clients index no longer renders a datagrid <table>. Its
# accessible name now comes from a visually-hidden <h2> ('Clients') that the card list references
# via aria-labelledby, plus role='list'. This request spec (CI-covered spec/requests) drives
# GET /clients as an admin and asserts that landmark wiring is present and correct. NON-VACUOUS:
# it checks the sr-only heading text, that the heading id is the list's aria-labelledby target,
# role='list', and that the heading precedes the list it labels. Attribute-order-independent.
RSpec.describe 'clients/index accessible list landmark (surface B)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'renders an sr-only Clients heading wired to the card list via aria-labelledby + role=list' do
    get clients_path
    expect(response).to have_http_status(:ok)
    body = response.body

    # A visually-hidden <h2> carrying the accessible name 'Clients', id=clients-list-heading.
    # Match id and class independently so the assertion does not depend on attribute order.
    h2 = body[/<h2\b[^>]*>\s*Clients\s*<\/h2>/i]
    expect(h2).to be_present
    expect(h2).to match(/id=["']clients-list-heading["']/)
    expect(h2).to match(/class=["'][^"']*\bsr-only\b/)

    # The card list is a role='list' <ul.record-cards> referencing that heading id.
    list_tag = body[/<ul\b[^>]*class=["'][^"']*\brecord-cards\b[^"']*["'][^>]*>/i]
    expect(list_tag).to be_present
    expect(list_tag).to match(/role=["']list["']/)
    expect(list_tag).to match(/aria-labelledby=["']clients-list-heading["']/)

    # Non-vacuous ordering: the labelling heading precedes the list it labels.
    heading_idx = body.index(h2)
    list_idx    = body.index(list_tag)
    expect(heading_idx).to be < list_idx
  end
end
