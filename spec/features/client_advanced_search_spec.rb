feature 'ClientAdvancedSearch', js: true do
  given(:admin) { create(:user, roles: 'admin') }

  background do
    login_as(admin)
    visit clients_path
  end

  scenario 'Advanced search link' do
    expect(page).to have_content 'Advanced Search'
  end

  scenario 'Advanced Search Text Field' do
    click_link 'Advanced Search'
    find(".rule-filter-container select option[value='given_name']", visible: false).select_option
    expect(page).to have_content 'Given Name'
    expect(page).to have_content 'is'
  end

  scenario 'Advanced Search Number Field' do
    click_link 'Advanced Search'
    find(".rule-filter-container select option[value='code']", visible: false).select_option
    expect(page).to have_content 'Code'
    expect(page).to have_content 'is'
  end
  xscenario 'Advanced Search Drop list Field' do
    click_link 'Advanced Search'
    find(".rule-filter-container select option[value='able_state']", visible: false).select_option
    expect(page).to have_content 'Able State'
    expect(page).to have_content 'is'
    expect(page).to have_content 'Accepted'
  end

  scenario 'Advanced Search Datepicker Field' do
    click_link 'Advanced Search'
    # BS5-Q3: placement_date (case-era field) is no longer in the SLO4HOME basic-rules
    # field list; date_of_birth exercises the same datepicker rule flow.
    find(".rule-filter-container select option[value='date_of_birth']", visible: false).select_option
    expect(page).to have_content 'Date of Birth'
    expect(page).to have_content 'is'
  end
end
