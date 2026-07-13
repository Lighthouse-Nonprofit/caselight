describe 'CaseNote' do
  let!(:user) { create(:user) }
  let!(:client) { create(:client,status: 'accepted', users: [user]) }
  let!(:fc_case){ create(:case, case_type: 'FC', client: client) }
  let!(:domain){ create(:domain, name: '1A') }
  let!(:assessment){ create(:assessment, client: client) }
  let!(:assessment_domain){ create(:assessment_domain, assessment: assessment, domain: domain) }

  before do
    login_as(user)
  end

  feature 'Create' do
    before do
      visit new_client_case_note_path(client)
    end

    def add_tasks(n)
      (1..n).each do |time|
        dismiss_datepicker
        find('.case-note-task-btn').click
        # BS5 Modal#hide() is a NO-OP mid-transition — wait for the fade to finish or the
        # success handler's hide gets swallowed and the modal never closes
        expect(page).to have_css('#tasksFromModal.show')
        sleep 0.5
        fill_in 'task_name', with: FFaker::Lorem.paragraph
        # ffaker 2.x returns a Date (Date.strptime(Date) raised); the datepicker is ISO now
        fill_in 'task_completion_date', with: FFaker::Time.date.strftime('%Y-%m-%d')
        find('.add-task-btn').trigger('click')
        # wait for the ajax round-trip to close the modal (sleep raced slower runs)
        expect(page).to have_no_css('#tasksFromModal.show', wait: 10)
      end
    end

    def remove_task(index)
      page.all('.task-arising a.remove-task')[index].click
    end

    scenario 'valid', js: true do
      fill_in 'case_note_meeting_date', with: '2017-04-01'
      fill_in 'Who was there during the visit or conversation?', with: 'Jonh'
      fill_in 'Note', with: 'This is valid'

      add_tasks(5)
      dismiss_datepicker
      find('#case-note-submit-btn').click
      
      sleep 1
      expect(page).to have_content('April 01, 2017')
      expect(page).to have_content('Jonh')
      expect(page).to have_content('This is valid')
    end

    xscenario 'invalid' do
      click_button 'Save'
      expect(page).to have_content("can't be blank")
    end
  end

  feature 'List' do
    let!(:case_note) { create(:case_note, client: client, assessment: assessment) }
    let!(:case_note_domain_group) { create(:case_note_domain_group, case_note: case_note, domain_group: domain.domain_group) }
    let!(:other_client) { create(:client,status: 'accepted', users: [user]) }
    let!(:other_fc_case){ create(:case, case_type: 'FC', client: other_client) }

    before do
      visit client_case_notes_path(client)
    end

    scenario 'link new case note' do
      expect(page).to have_link('New case note')
    end

    scenario 'case note date' do
      expect(page).to have_content case_note.meeting_date.strftime('%B %d, %Y')
    end

    scenario 'case note domain' do
      expect(page).to have_content domain.identity
    end

    scenario 'case note score' do
      expect(page).to have_content assessment_domain.score
    end

    scenario 'case note content' do
      expect(page).to have_content case_note_domain_group.note
    end

    # BS5-Q3: the old `not_to have_link(nil)` matched nothing under Capybara 2 (nil
    # locator) and matches EVERY link under Capybara 3 — the recoverable intent is
    # that a case note without an assessment still lists cleanly.
    scenario 'no assessment' do
      expect(page).to have_content(case_note_domain_group.note)
      expect(page).not_to have_css('.domain-score')
    end
  end


end
