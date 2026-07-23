# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (D3/R9) — selecting a sidebar menu item collapses the sidebar again.
# Desktop semantics: the leaf-link click writes a cl_sidebar=mini cookie; the NEXT page
# renders body.mini-navbar server-side (icon rail, no FOUC). The hamburger re-expands and
# persists the choice the same way.
describe 'sidebar collapse on menu select', js: true do
  let!(:admin) { create(:user, roles: 'admin') }

  before { login_as(admin) }

  scenario 'a leaf menu click collapses the sidebar on the next page, and it stays collapsed' do
    visit root_path
    expect(page).not_to have_css('body.mini-navbar')

    within '#side-menu' do
      first("a[href*='clients']").click
    end
    expect(page).to have_css('body.mini-navbar')

    visit root_path # an unrelated navigation stays collapsed (cookie)
    expect(page).to have_css('body.mini-navbar')
  end

  scenario 'the hamburger re-expands and the choice persists' do
    visit root_path
    within('#side-menu') { first("a[href*='clients']").click }
    expect(page).to have_css('body.mini-navbar')

    find('.navbar-minimalize').click
    expect(page).not_to have_css('body.mini-navbar')

    visit root_path
    expect(page).not_to have_css('body.mini-navbar')
  end
end
