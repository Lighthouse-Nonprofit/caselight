describe 'Domain' do
  let!(:admin){ create(:user, roles: 'admin') }
  let!(:domain_group){ create(:domain_group) }
  let!(:domain){ create(:domain) }
  let!(:other_domain){ create(:domain) }
  let!(:task){ create(:task, domain: other_domain) }
  before do
    login_as(admin)
  end
  feature 'List' do
    before do
      visit domains_path
    end
    scenario 'name' do
      expect(page).to have_content(domain.name)
      expect(page).to have_content(other_domain.name)
    end

    scenario 'new link' do
      expect(page).to have_link('Add New Domain', href: new_domain_path)
    end
    scenario 'edit link' do
      expect(page).to have_link(nil, href: edit_domain_path(domain))
    end
    scenario 'delete link' do
      expect(page).to have_css("a[href='#{domain_path(domain)}'][data-method='delete']")
    end
  end

  feature 'Create', js: true do
    let!(:another_domain) { create(:domain, name: 'Another Domain') }
    before do
      visit new_domain_path
    end
    scenario 'valid' do
      fill_in 'Name', with: 'Domain Name'
      fill_in 'Identity', with: 'Domain Identity'
      click_button 'Save'
      sleep 1
      expect(page).to have_content('Domain Name')
      expect(page).to have_content('Domain Identity')
    end
    scenario 'invalid' do
      fill_in 'Name', with: 'Another Domain'
      fill_in 'Identity', with: 'Domain Identity'
      click_button 'Save'
      expect(page).to have_content('has already been taken')
    end
  end

  feature 'Edit' do
    before do
      visit edit_domain_path(domain)
    end
    scenario 'valid', js: true do
      fill_in 'Name', with: 'Updated Domain Name'
      click_button 'Save'
      sleep 1
      expect(page).to have_content('Updated Domain Name')
    end
    scenario 'invalid' do
      fill_in 'Name', with: ''
      click_button 'Save'
      expect(page).to have_content("can't be blank")
    end
  end

  feature 'Delete', js: true do
    before do
      visit domains_path
    end
    scenario 'success' do
      find("a[href='#{domain_path(domain)}'][data-method='delete']").click
      sleep 1
      expect(page).not_to have_content(domain.name)
    end
    scenario 'disable delete' do
      expect(page).to have_css("a[href='#{domain_path(other_domain)}'][data-method='delete'][class='btn btn-outline btn-danger margin-left disabled']")
    end
  end

  feature 'Sensitivity (Phase 5.2b)' do
    scenario 'new form renders the three sensitivity levels' do
      visit new_domain_path
      expect(page).to have_select('domain_sensitivity',
        options: ['Standard — anyone who can read the record',
                  'Restricted — caseload / role-scoped readers',
                  'Emergency only — break-glass access'])
    end

    scenario 'create persists the chosen sensitivity', js: true do
      visit new_domain_path
      fill_in 'Name', with: 'Mental Health'
      fill_in 'Identity', with: 'Mental Health & Well-Being'
      select 'Restricted — caseload / role-scoped readers', from: 'domain_sensitivity'
      click_button 'Save'
      sleep 1
      expect(Domain.find_by(name: 'Mental Health').sensitivity).to eq('restricted')
    end

    scenario 'edit updates the sensitivity', js: true do
      target = create(:domain, sensitivity: 'standard')
      visit edit_domain_path(target)
      select 'Emergency only — break-glass access', from: 'domain_sensitivity'
      click_button 'Save'
      sleep 1
      expect(target.reload.sensitivity).to eq('emergency_only')
    end

    scenario 'create defaults to standard when left untouched', js: true do
      visit new_domain_path
      fill_in 'Name', with: 'Education'
      fill_in 'Identity', with: 'Education & Vocational'
      click_button 'Save'
      sleep 1
      expect(Domain.find_by(name: 'Education').sensitivity).to eq('standard')
    end
  end
end
