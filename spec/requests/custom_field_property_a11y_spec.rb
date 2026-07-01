# frozen_string_literal: true
require 'rails_helper'

# Section 508 / WCAG 2.1 AA -- Unit 13-15 surface A. Drives the REAL
# custom_field_properties#new render (which renders custom_field_properties/_form.haml ->
# shared/fields/*.haml and, for a file field, shared/form_builder/_file_field.haml) and asserts
# the added a11y attributes appear in response.body. CI runs a js-EXCLUDING subset, so this is a
# request spec (rendered server-side), not capybara/axe.
#
# QUOTE HANDLING (verified against HAML 5.2.2 + simple_form 5.4.1 in the dev container):
#   * Attributes we set on a %tag hash (label for=, %div role=/aria-labelledby=, %abbr aria-hidden=,
#     %span id=, %i aria-hidden=) are emitted by HAML with SINGLE quotes (e.g. for='...').
#   * Attributes Rails form helpers emit on the <input>/<select> (id=, aria-describedby=,
#     aria-required=) are emitted with DOUBLE quotes.
# So HAML-tag assertions use a quote-agnostic regex (["']) and input assertions use include("...\"").
RSpec.describe 'Custom-form field renderers a11y (surface A)', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:client)   { create(:client) }

  # One CustomField exercising every render path. Distinct labels so ids are unambiguous.
  let!(:cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'A11y Intake', sensitivity: 'standard',
      fields: [
        { 'type' => 'text',           'label' => 'Full Name',   'required' => true },
        { 'type' => 'textarea',       'label' => 'Story',       'required' => false },
        { 'type' => 'number',         'label' => 'Household',   'required' => false },
        { 'type' => 'date',           'label' => 'Arrival',     'required' => false },
        { 'type' => 'select',         'label' => 'Origin',      'required' => false, 'values' => [{ 'label' => 'Syria' }, { 'label' => 'Sudan' }] },
        { 'type' => 'radio_group',    'label' => 'Case Status', 'required' => true,  'values' => [{ 'label' => 'Open' }, { 'label' => 'Closed' }] },
        { 'type' => 'checkbox_group', 'label' => 'Needs',       'required' => false, 'values' => [{ 'label' => 'Housing' }, { 'label' => 'Food' }] }
      ])
  end

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  subject(:body) do
    get new_client_custom_field_property_path(client, custom_field_id: cf.id)
    expect(response).to have_http_status(:ok)
    response.body
  end

  # HAML-tag attr (single-quoted) matcher
  def haml_attr(name, value)
    /#{Regexp.escape(name)}=["']#{Regexp.escape(value)}["']/
  end

  it 'labels the text input: <label for> matches the input id and points help via aria-describedby' do
    fid = 'custom_field_property_properties_Full_Name'
    expect(body).to match(haml_attr('for', fid))            # label for= (HAML, single-quoted)
    expect(body).to include(%(id="#{fid}"))                 # input id= (Rails, double-quoted)
    expect(body).to include(%(aria-describedby="#{fid}_help"))
    expect(body).to match(haml_attr('id', "#{fid}_help"))   # help-block span id= (HAML)
  end

  it 'marks a required control aria-required="true" and its decorative asterisk aria-hidden' do
    expect(body).to include('aria-required="true"')          # Full Name / Case Status required (Rails input)
    expect(body).to match(haml_attr('aria-hidden', 'true'))  # the <abbr> (HAML)
  end

  it 'does NOT emit aria-required on an optional control (attribute dropped when nil)' do
    story_id = 'custom_field_property_properties_Story'
    expect(body).to include(%(id="#{story_id}"))
    expect(body).not_to match(/id="#{Regexp.escape(story_id)}"[^>]*aria-required="true"/)
  end

  it 'labels the textarea, number, and select the same way (for= == id)' do
    %w[Story Household Origin].each do |lbl|
      fid = "custom_field_property_properties_#{lbl}"
      expect(body).to match(haml_attr('for', fid)), "missing label for=#{fid}"
      expect(body).to include(%(id="#{fid}")),       "missing input id=#{fid}"
    end
  end

  it 'exposes the radio_group as role=radiogroup with aria-labelledby -> heading label id' do
    gid = 'custom_field_property_properties_Case_Status'
    expect(body).to match(haml_attr('role', 'radiogroup'))
    expect(body).to match(haml_attr('id', "#{gid}_label"))
    expect(body).to match(haml_attr('aria-labelledby', "#{gid}_label"))
    expect(body).to match(haml_attr('aria-describedby', "#{gid}_help"))
  end

  it 'exposes the checkbox_group as role=group with aria-labelledby -> heading label id' do
    gid = 'custom_field_property_properties_Needs'
    expect(body).to match(haml_attr('role', 'group'))
    expect(body).to match(haml_attr('id', "#{gid}_label"))
    expect(body).to match(haml_attr('aria-labelledby', "#{gid}_label"))
  end

  it 'hides the decorative calendar icon on the date field from screen readers' do
    # the date partial is the only fa-calendar-check-o; it must be aria-hidden (HAML single-quoted)
    expect(body).to match(/fa-calendar-check-o[^>]*aria-hidden=["']true["']|aria-hidden=["']true["'][^>]*fa-calendar-check-o/)
  end
end