describe 'Task' do
  let!(:user){ create(:user, calendar_integration: true) }
  let!(:client){ create(:client, users: [user]) }
  let!(:domain){ create(:domain) }
  let!(:overdue_task){ create(:task, client: client, completion_date: Time.zone.today - 6.month) }
  let!(:today_task){ create(:task, client: client, completion_date: Time.zone.today) }
  let!(:upcoming_task){ create(:task, client: client, completion_date: Time.zone.today + 6.month) }
  let!(:incomplete_task){ create(:task, completed: false) }
  before do
    login_as(user)
  end
  feature 'List' do
    before do
      visit client_tasks_path(client)
    end
    scenario 'overdue task' do
      panel = page.all(:css, '.card').select { |p| p.all(:css, '.card-header').select { |pp| pp.text.include?('Overdue Tasks') }.first }.first
      expect(panel).to have_content(overdue_task.name)
      expect(panel).to have_content(overdue_task.domain.name)
      expect(panel).to have_content(overdue_task.completion_date.strftime("%B %d, %Y"))
    end
    scenario 'today task' do
      panel = page.all(:css, '.card').select { |p| p.all(:css, '.card-header').select { |pp| pp.text.include?('Today Tasks') }.first }.first
      expect(panel).to have_content(today_task.name)
      expect(panel).to have_content(today_task.domain.name)
      expect(panel).to have_content(today_task.completion_date.strftime("%B %d, %Y"))
    end
    scenario 'upcoming task' do
      panel = page.all(:css, '.card').select { |p| p.all(:css, '.card-header').select { |pp| pp.text.include?('Upcoming Tasks') }.first }.first
      expect(panel).to have_content(upcoming_task.name)
      expect(panel).to have_content(upcoming_task.domain.name)
      expect(panel).to have_content(upcoming_task.completion_date.strftime("%B %d, %Y"))
    end
    scenario 'edit link' do
      expect(page).to have_link(nil)
      expect(page).to have_link(nil)
      expect(page).to have_link(nil)
    end
    scenario 'delete link' do
      expect(page).to have_css("a[href='#{client_task_path(client, overdue_task)}'][data-method='delete']")
      expect(page).to have_css("a[href='#{client_task_path(client, today_task)}'][data-method='delete']")
      expect(page).to have_css("a[href='#{client_task_path(client, upcoming_task)}'][data-method='delete']")
    end

    scenario 'new link' do
      expect(page).to have_link('New Task')
    end

    scenario 'no incomplete task' do
      expect(page).not_to have_content(incomplete_task)
    end
  end
  feature 'Create' do
    before do
      visit new_client_task_path(client)
    end
    scenario 'valid', js: true do
      fill_in 'Enter task details', with: 'My Task'
      fill_in 'Completion Date', with: '2017-08-01'
      dismiss_datepicker
      click_button 'Save'
      sleep 1
      expect(page).to have_content('My Task')
      expect(page).to have_content('August 01, 2017')

      # Data-task batch (2026-07): the materialized calendars table is gone — the calendar
      # feed reads tasks directly, so creating the task IS the calendar entry.
      task = client.tasks.find_by(name: 'My Task')
      expect(task).to be_present
      expect(task.users.size).to eq(2)
    end
    scenario 'invalid' do
      click_button 'Save'
      expect(page).to have_content("Please review the problems below")
    end
  end

  feature 'Update' do
    before do
      visit edit_client_task_path(client, upcoming_task)
    end
    scenario 'valid', js: true do
      fill_in 'Enter task details', with: 'Task Updated'
      click_button 'Save'
      sleep 1
      expect(page).to have_content('Task Updated')
    end
    scenario 'invalid' do
      fill_in 'Enter task details', with: ''
      click_button 'Save'
      expect(page).to have_content("Please review the problems below")
    end
  end

  feature 'Delete', js: true do
    before do
      visit client_tasks_path(client)
    end
    scenario 'successful' do
      find("a[href='#{client_task_path(client, overdue_task)}'][data-method='delete']").click
      sleep 1
      expect(page).to have_content('Task has successfully been deleted')
    end
  end
end
