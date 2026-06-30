# frozen_string_literal: true
require 'rails_helper'

# Regression (P1): display_custom_properties used `content_tag :span do ... concat value ... end`.
# Under HAML capture, `concat` appends to the OUTER page buffer (the <td>), so content_tag
# snapshots the partially-rendered page INTO the span -- each value rendered once, then again
# inside a junk <span> holding the escaped, <br/>-joined dump of the surrounding markup.
# This drives the real index.haml render; the leak only appears with an active outer buffer,
# so a bare helper call cannot reproduce it -- hence a request spec. spec/requests is CI-covered.
RSpec.describe 'CustomFieldProperty index render (no buffer leak)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:client)   { create(:client) }
  let!(:cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Intake Notes',
           sensitivity: 'standard', fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
  end

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  def render_index_with(props)
    client.custom_field_properties.create!(custom_field: cf, properties: props)
    get client_custom_field_properties_path(client, custom_field_id: cf.id)
    expect(response).to have_http_status(:ok)
    response.body
  end

  it 'renders the value in a clean span, escaped, newline->br, with no page-markup leak' do
    body = render_index_with('Diagnosis' => "PTSD <b>flag</b>\nstable")
    # value escaped (no stored XSS) + newline preserved (br form tolerant: tag.br emits <br>)
    expect(body).to match(%r{PTSD &lt;b&gt;flag&lt;/b&gt;<br\s*/?>stable})
    expect(body).not_to include('PTSD <b>flag</b>')
    # value appears exactly once (the leak rendered it twice)
    expect(body.scan('PTSD &lt;b&gt;flag&lt;/b&gt;').size).to eq(1)
    # the hallmark of the bug: the page's own markup dumped (escaped) into a span
    expect(body).not_to match(/<span>&lt;(div|table|tr|td|h5)/)
  end

  it 'does not 500 when a stored value is nil (missing key)' do
    expect { render_index_with('Other' => 'kept') }.not_to raise_error
  end
end
