# frozen_string_literal: true
require 'rails_helper'

# Section 508 / WCAG -- surface A, file-upload renderer. A file-type custom field routes through
# custom_field_properties/_form.haml -> shared/form_builder/_attachment.haml -> _file_field.haml
# (NOT shared/fields/_file.haml, which is dead code). Asserts the file input is labeled (for=/id),
# aria-required when required, linked to its .hidden help-block via aria-describedby, and that the
# 'repuired' typo is gone. Same quote convention as the sibling spec: label for= / span id= are
# HAML (single-quoted -> quote-agnostic regex); the <input> id=/aria-describedby=/aria-required=
# are Rails-emitted (double-quoted).
RSpec.describe 'Custom-form file field a11y (surface A / _file_field)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:client)   { create(:client) }

  let!(:cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Docs', sensitivity: 'standard',
      fields: [{ 'type' => 'file', 'label' => 'Passport Scan', 'name' => 'file-01', 'required' => true }])
  end

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  subject(:body) do
    get new_client_custom_field_property_path(client, custom_field_id: cf.id)
    expect(response).to have_http_status(:ok)
    response.body
  end

  def haml_attr(name, value)
    /#{Regexp.escape(name)}=["']#{Regexp.escape(value)}["']/
  end

  it 'derives the file id from property name and wires label for=/aria-describedby to it' do
    fid = 'fbattach_file-01'
    expect(body).to match(haml_attr('for', fid))                    # label for= (HAML)
    expect(body).to include(%(id="#{fid}"))                         # file input id= (Rails)
    expect(body).to include(%(aria-describedby="#{fid}_help"))      # (Rails)
    expect(body).to match(haml_attr('id', "#{fid}_help"))          # .hidden help-block span id= (HAML)
  end

  it 'marks the required file input aria-required and drops the repuired typo' do
    expect(body).to include('aria-required="true"')
    expect(body).not_to include('repuired')
  end
end