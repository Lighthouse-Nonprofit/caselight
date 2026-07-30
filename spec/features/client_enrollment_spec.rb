describe 'Client Enrollment' do
  let!(:admin){ create(:user, roles: 'admin') }
  let!(:client) { create(:client, given_name: 'Adam', family_name: 'Eve', local_given_name: 'Romeo', local_family_name: 'Juliet', date_of_birth: 10.years.ago) }
  let!(:domain) { create(:domain) }
  let!(:program_stream) { create(:program_stream, name: 'Fitness') }
  let!(:program_stream_active) { create(:program_stream, name: 'Second Fitness') }
  let!(:program_stream_exited) { create(:program_stream, name: 'Third Fitness') }
  let!(:domain_program_stream) { create(:domain_program_stream, domain: domain, program_stream: program_stream) }
  let!(:domain_program_stream_exited) { create(:domain_program_stream, domain: domain, program_stream: program_stream_exited) }
  let!(:domain_program_stream_active) { create(:domain_program_stream, domain: domain, program_stream: program_stream_active) }

  let!(:second_program_stream) { create(:program_stream, name: 'second name') }
  let!(:client_enrollment) { create(:client_enrollment, program_stream: program_stream, client: client) }
  let!(:client_enrollment_active) { create(:client_enrollment, program_stream: program_stream_active, client: client, status: 'Active') }
  let!(:client_enrollment_exited) { create(:client_enrollment, program_stream: program_stream_exited, client: client, status: 'Exited') }

  before do
    login_as admin
  end

  # (P2: the legacy client_enrolled_programs listing feature retired with its page — the
  # 'Consolidated Programs tab' feature below owns this surface now.)

  # Investor UX round (2026-07): the Programs tab is per-program sub-tabs + an Add Program
  # modal (rack_test sees all panes — no CSS visibility).
  feature 'Consolidated Programs tab' do
    before do
      program_stream_exited.reload
      program_stream_exited.update_columns(completed: true)
      second_program_stream.reload
      second_program_stream.update_columns(completed: true)

      visit client_client_enrollments_path(client)
    end

    scenario 'one sub-tab per ever-enrolled program' do
      expect(page).to have_css("#program-tab-#{program_stream.id}", text: program_stream.name)
      expect(page).to have_css("#program-tab-#{program_stream_active.id}", text: program_stream_active.name)
      expect(page).to have_css("#program-tab-#{program_stream_exited.id}", text: program_stream_exited.name)
      expect(page).not_to have_content('Programs List') # the old two-table page is gone
    end

    scenario 'exited pane offers Re-enroll; active pane offers Exit Program' do
      expect(page).to have_link('Re-enroll')
      expect(page).to have_link('Exit Program')
    end

    scenario 'the Add Program modal lists only never-enrolled complete streams' do
      within('#add-program-modal') do
        expect(page).to have_content(second_program_stream.name)
        expect(page).to have_link('Enroll')
        expect(page).not_to have_content(program_stream.name)
      end
    end

    scenario 'the timeline leads with the Forms column' do
      expect(page.body).to match(%r{<th>Forms</th>\s*<th>Date</th>\s*<th>Actions</th>})
    end
  end

  feature 'Enroll', js: true do
    before do
      program_stream.reload
      program_stream.update_columns(completed: true)

      second_program_stream.reload
      second_program_stream.update_columns(completed: true)
      visit client_client_enrollments_path(client)
      # Investor UX round (2026-07): Enroll lives in the Add Program modal now.
      click_button('Add Program')
      within('#add-program-modal') { click_link('Enroll') }
    end

    scenario 'Valid' do
      within('#new_client_enrollment') do
        find('.numeric').set(3)
        find('#enrollment_date').set(FFaker::Time.date)
        find('#client_enrollment_properties_description').set('this is testing')
        find('input[type="email"]').set('test@example.com')

        dismiss_datepicker
        click_button 'Save'
      end
      # lands on the new program's pane; the values live behind the timeline's View link
      expect(page).to have_content('Enrollment has been successfully created.')
      expect(page).to have_css("#program-tab-#{second_program_stream.id}", text: second_program_stream.name)
      within("#program-pane-#{second_program_stream.id}") { first(:link, 'View').click }
      expect(page).to have_content('3')
      expect(page).to have_content('this is testing')
      expect(page).to have_content('test@example.com')
    end

    scenario 'Invalid' do
      within('#new_client_enrollment') do
        find('.numeric').set(6)
        find('#client_enrollment_properties_description').set('')
        find('input[type="email"]').set('testexample')

        click_button 'Save'
      end
      expect(page).to have_css('div.has-error')
    end
  end

  feature 'Report timeline (the pane)' do
    before do
      visit client_client_enrollments_path(client, program_stream_id: program_stream.id)
    end

    scenario 'Date' do
      expect(page).to have_content(client_enrollment.enrollment_date.strftime '%d %B, %Y')
    end

    scenario 'View Link' do
      expect(page).to have_link('View')
    end
  end

  feature 'Show' do
    before do
      visit client_client_enrollment_path(client, client_enrollment, program_stream_id: program_stream.id)
    end

    scenario 'Date' do
      expect(page).to have_content(client_enrollment.enrollment_date.strftime '%d %B, %Y')
    end

    scenario 'Age' do
      expect(page).to have_content('3')
    end

    scenario 'Email' do
      expect(page).to have_content('test@example.com')
    end

    scenario 'Description' do
      expect(page).to have_content('this is testing')
    end

    scenario 'Back Link' do
      expect(page).to have_link('Back')
    end

    scenario 'Edit Link' do
      expect(page).to have_link(nil)
    end

    # xscenario 'Delete Link' do
    #   expect(page).to have_css("a[href='#{client_client_enrollment_path(client, client_enrollment, program_stream_id: program_stream.id)}'][data-method='delete']")
    # end
  end

  feature 'Update', js: true do
    before do
      visit edit_client_client_enrollment_path(client, client_enrollment, program_stream_id: program_stream.id)
    end

    scenario 'success' do
      find('input[type="text"]:last-child').set('this is editing')
      find('input[type="submit"]').click
      expect(page).to have_content('this is editing')
    end

    scenario 'fail' do
      find('input[type="text"]:last-child').set('')
      find('input[type="submit"]').click
      expect(page).to have_css('div.has-error')
    end
  end

  feature 'Destroy', js: true do
    # Investor UX round (2026-07): delete moved to the EDIT page footer (it cascades the
    # program's trackings + exit record; the show page keeps pencil + Back only).
    before do
      visit edit_client_client_enrollment_path(client, client_enrollment, program_stream_id: program_stream.id)
    end

    scenario 'success' do
      find("a[data-method='delete'][href*='#{client_client_enrollment_path(client, client_enrollment)}']").click
      expect(page).to have_content('Enrollment has been successfully deleted.')
      expect(page).not_to have_css("#program-tab-#{program_stream.id}")
    end
  end
end
