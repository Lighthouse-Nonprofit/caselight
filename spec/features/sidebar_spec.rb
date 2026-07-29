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

  # ------------------------------------------------------------------------------------------------
  # C1 — the collapsed rail is a first-class navigation surface: leaf icons navigate, every icon
  # has a live tooltip (mini only), the labels stay in the accessible tree, and the profile
  # dropdown (with Log out) is reachable — it used to be display:none'd away entirely.
  # ------------------------------------------------------------------------------------------------
  def collapse_rail!
    visit root_path
    within('#side-menu') { first("a[href*='clients']").click } # writes cl_sidebar=mini
    expect(page).to have_css('body.mini-navbar')
  end

  scenario 'mini rail: a leaf icon still navigates' do
    collapse_rail!
    visit root_path
    within('#side-menu') { first("a[href*='families']").click }
    expect(page).to have_current_path(%r{/families}, url: false)
    expect(page).to have_css('body.mini-navbar') # stays collapsed
  end

  scenario 'mini rail: hovering an icon shows its navy tooltip; expanded mode shows none' do
    collapse_rail!
    visit root_path
    page.find('#side-menu > li > a', match: :first).hover
    expect(page).to have_css('.tooltip.cl-nav-tooltip', text: 'Dashboards')

    find('.navbar-minimalize').click # expand — tooltips disarm
    expect(page).not_to have_css('body.mini-navbar')
    page.find('#side-menu > li > a', match: :first).hover
    expect(page).not_to have_css('.tooltip.cl-nav-tooltip', wait: 1)
  end

  scenario 'mini rail: labels and counts remain in the accessible tree (visually hidden, not gone)' do
    collapse_rail!
    visit root_path
    expect(page).to have_css('#side-menu a .nav-label', text: 'Dashboards', visible: :all)
    # visually-hidden() clips to a 1x1 box (NOT display:none — that would drop the accessible
    # name). Capybara counts a 1x1 element as :visible, so assert the geometry instead.
    width = page.evaluate_script(
      "Math.round(document.querySelector('#side-menu a .nav-label').getBoundingClientRect().width)"
    )
    expect(width).to be <= 1
  end

  scenario 'mini rail: the profile dropdown is reachable and Log out is visible' do
    collapse_rail!
    visit root_path
    expect(page).to have_css('.profile-element__glyph', visible: :visible)
    find('.profile-element .dropdown-toggle').click
    within('.profile-element .dropdown-menu') do
      expect(page).to have_link('Log Out', visible: :visible)
        .or have_link('Log out', visible: :visible)
    end
  end

  # ------------------------------------------------------------------------------------------------
  # C2 — the #manage flyout: the one submenu item gets a titled flyout panel in desktop-mini
  # (it was a dead click — metisMenu preventDefault + force-hidden accordion). Expanded mode must
  # keep the metisMenu accordion untouched, and common.js's SYNTHETIC open-on-load click must
  # never pop the flyout.
  # ------------------------------------------------------------------------------------------------
  scenario 'mini rail: #manage opens a titled flyout and its links navigate (rail stays mini)' do
    collapse_rail!
    visit root_path
    find('#manage').click
    expect(page).to have_css('.cl-sidebar-flyout.show')
    expect(page).to have_css('.cl-sidebar-flyout__title', text: /manage/i) # rendered uppercase
    expect(page).to have_css('#manage[aria-expanded="true"]')

    within('.cl-sidebar-flyout') { click_link 'Agencies' }
    expect(page).to have_current_path(%r{/agencies})
    expect(page).to have_css('body.mini-navbar')
    expect(page).not_to have_css('.cl-sidebar-flyout.show')
  end

  scenario 'mini rail: the flyout flattens the third level under a Progress Note subheader' do
    collapse_rail!
    visit root_path
    find('#manage').click
    within('.cl-sidebar-flyout') do
      expect(page).to have_css('.cl-sidebar-flyout__subheader', text: /progress note/i) # rendered uppercase
      expect(page).to have_css('li.cl-sidebar-flyout__nested a', text: 'Interventions')
    end
  end

  scenario 'mini rail: Escape closes the flyout and refocuses #manage; outside click closes too' do
    collapse_rail!
    visit root_path
    find('#manage').click
    expect(page).to have_css('.cl-sidebar-flyout.show')
    expect(page).to have_current_path(%r{/dashboards|^/$}, url: false) # opening must NOT navigate
    # NOT page.send_keys(:escape): cuprite routes that through the focused NODE's #type, which
    # re-clicks the node to focus it — and the flyout auto-focuses its first LINK, so send_keys
    # would navigate. Dispatch the keydown the way a keyboard does.
    page.execute_script("document.dispatchEvent(new KeyboardEvent('keydown', { key: 'Escape', bubbles: true }))")
    expect(page).not_to have_css('.cl-sidebar-flyout.show')
    expect(page).to have_current_path(%r{/dashboards|^/$}, url: false) # escape must NOT navigate
    expect(page.evaluate_script('document.activeElement.id')).to eq('manage')

    find('#manage').click
    expect(page).to have_css('.cl-sidebar-flyout.show')
    find('#page-wrapper').click
    expect(page).not_to have_css('.cl-sidebar-flyout.show')
  end

  scenario 'expanded mode: #manage still opens the in-rail metisMenu accordion (regression guard)' do
    visit root_path
    expect(page).not_to have_css('body.mini-navbar')
    find('#manage').click
    expect(page).to have_css('#side-menu .nav-second-level a', text: 'Agencies', visible: :visible)
    expect(page).not_to have_css('.cl-sidebar-flyout.show')
  end

  scenario 'mini rail: the synthetic open-on-load click (nested item active) never pops the flyout' do
    collapse_rail!
    visit interventions_path # nested-active page -> common.js triggers #manage/#pro-nav clicks
    expect(page).to have_css('body.mini-navbar')
    expect(page).not_to have_css('.cl-sidebar-flyout.show', wait: 1.5)
  end
end
