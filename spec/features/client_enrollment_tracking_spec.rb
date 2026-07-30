describe ClientEnrollmentTracking, 'Client Enrollment Tracking' do
  let!(:admin){ create(:user, roles: 'admin') }
  let!(:client) { create(:client, given_name: 'Adam', family_name: 'Eve', local_given_name: 'Romeo', local_family_name: 'Juliet', date_of_birth: 10.years.ago) }
  let!(:program_stream) { create(:program_stream, name: 'Fitness') }
  let!(:client_enrollment) { create(:client_enrollment, program_stream: program_stream, client: client) }
  let!(:tracking) { create(:tracking, name: 'Soccer', program_stream: program_stream) }
  let!(:client_enrollment_tracking) { create(:client_enrollment_tracking, client_enrollment: client_enrollment, tracking: tracking) }

  before do
    login_as admin
  end

  # Investor UX round (2026-07, P1/P2): tracking creation starts from the program pane's
  # Add Tracking action; the legacy trackings grid + report pages are gone (entries live on
  # the pane timeline, values on show, delete on the edit page).
  feature 'Create', js: true do
    before do
      program_stream.reload
      program_stream.update_columns(completed: true)
      visit client_client_enrollments_path(client)
      click_link('Add Tracking')
    end

    scenario 'Valid', js: true do
      expect(page).to have_content('Adam Eve (Romeo Juliet) - Soccer - Fitness')
      within('#new_client_enrollment_tracking') do
        find('.numeric').set(4)
        find('input[type="text"]').set('Good client')
        find('input[type="email"]').set('test@example.com')

        click_button 'Save'
      end
      expect(page).to have_content('Tracking Program has been successfully created.')
      expect(page).to have_content('Tracking (Soccer)')
    end

    scenario 'Invalid' do
      expect(page).to have_content('Adam Eve (Romeo Juliet) - Soccer - Fitness')
      within('#new_client_enrollment_tracking') do
        find('.numeric').set(6)
        find('input[type="text"]').set('')
        find('input[type="email"]').set('cicambodianfamilies')

        click_button 'Save'
      end
      expect(page).to have_css('div.has-error')
    end
  end

  feature 'Show' do
    before do
      visit client_client_enrollment_client_enrollment_tracking_path(client, client_enrollment, client_enrollment_tracking, tracking_id: tracking.id)
    end

    scenario 'Age' do
      expect(page).to have_content('3')
    end

    scenario 'E-mail' do
      expect(page).to have_content('test@example.com')
    end

    scenario 'Description' do
      expect(page).to have_content('this is testing')
    end

    scenario 'Back Link' do
      expect(page).to have_link('Back')
    end
  end

  feature 'Update', js: true do
    before do
      visit edit_client_client_enrollment_client_enrollment_tracking_path(client, client_enrollment, client_enrollment_tracking, tracking_id: tracking.id)
    end

    scenario 'Delete lives on the edit page (investor UX round)' do
      expect(page).to have_css(".ibox-footer a[data-method='delete']")
    end

    scenario 'success' do
      expect(page).to have_content('Adam Eve (Romeo Juliet) - Soccer - Fitness')
      find('input[type="text"]').set('this is editing')
      find('input[type="submit"]').click
      # P2: update lands on the program pane; the edited value lives behind the timeline View
      expect(page).to have_content('Tracking Program has been successfully updated.')
      first(:link, 'View').click
      expect(page).to have_content('this is editing')
    end

    xscenario 'fail' do
      expect(page).to have_content('Adam Eve (Romeo Juliet) - Soccer - Fitness')
      find('input[type="text"]').set('')
      find('input[type="submit"]').click
      expect(page).to have_css('div.has-error')
    end
  end

  # feature 'Destroy', js: true do
  #   before do
  #     visit client_client_enrollment_client_enrollment_tracking_path(client, client_enrollment, client_enrollment_tracking, tracking_id: tracking.id)
  #   end

  #   scenario 'success' do
  #     save_and_open_screenshot
  #     find("a[data-method='delete'][href='#{client_client_enrollment_client_enrollment_tracking_path(client, client_enrollment, client_enrollment_tracking, tracking_id: tracking.id)}']").click
  #     save_and_open_screenshot
  #     expect(page).to have_content('Tracking has been successfully deleted')
  #   end
  # end
end
