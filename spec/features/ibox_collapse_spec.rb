# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (D2/R8) — the normalized .ibox collapse contract: `.collapsed` on the .ibox is
# the single source of truth (server pre-collapses empty sections; JS toggles the class and
# slideToggles the body; the chevron glyph is CSS-owned). Verified on the client Forms page,
# where an empty filled-forms section starts collapsed and the available-forms section starts
# expanded.
describe 'ibox section collapse', js: true do
  let!(:admin)  { create(:user, roles: 'admin') }
  let!(:client) { create(:client, state: 'accepted', users: [admin]) }
  let!(:free_cf) do
    create(:custom_field, entity_type: 'Client', form_title: 'Collapse Spec Form',
           fields: [{ 'type' => 'text', 'label' => 'Anything' }])
  end

  before { login_as(admin) }

  scenario 'an empty section starts collapsed and expands on click' do
    visit client_forms_path(client)

    collapsed = find('.ibox.collapsed', match: :first)
    expect(collapsed).to have_css('.ibox-content', visible: :hidden)

    collapsed.find('.collapse-link').click
    expect(page).to have_css('.ibox:not(.collapsed) .ibox-content', visible: :visible, match: :first)
    expect(page).to have_content('No forms filled yet.')
  end

  scenario 'a populated section starts expanded and collapses on click' do
    # Investor UX round (2026-07): the Available-forms section became the Add-new-form picker,
    # so the POPULATED section under test is the filled-forms table.
    client.custom_field_properties.create!(custom_field: free_cf, properties: { 'Anything' => 'x' })
    visit client_forms_path(client)

    filled = find('.ibox', text: 'Collapse Spec Form')
    expect(filled).not_to match_css('.collapsed')

    filled.find('.collapse-link').click
    expect(filled).to match_css('.collapsed')
    expect(filled).to have_css('.ibox-content', visible: :hidden)
  end
end
