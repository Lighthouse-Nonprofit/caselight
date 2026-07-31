describe Calendar do
  describe 'associations' do
    it { is_expected.to belong_to(:user) }
  end

  describe 'class methods' do
    let!(:user_1){ create(:user) }
    let!(:user_2){ create(:user) }
    let!(:client_1){ create(:client, users: [user_1, user_2]) }
    let!(:task_1){ create(:task, client: client_1, name: 'My Task', completion_date: Date.today) }
    context 'populate_tasks' do
      before do
        task_1.reload
        Calendar.populate_tasks(task_1)
      end
      it 'should include tasks of case workers of the client' do
        expect(Calendar.pluck(:user_id)).to include(user_1.id, user_2.id)
      end
    end

    context 'update_tasks' do
      before do
        Calendar.populate_tasks(task_1)

        title      = "#{task_1.domain.name} - #{task_1.name}"
        start_date = task_1.completion_date
        # C1 (TZ flip): ASSIGNING a Date to a datetime column casts to Time.zone midnight,
        # but a Date in a WHERE bind serializes as UTC midnight — 7h apart under LA time.
        # Query with explicit zone times.
        calendars = Calendar.where(title: title,
                                   start_date: start_date.in_time_zone,
                                   end_date: (start_date + 1.day).in_time_zone)

        @task_params = { name: 'My Task Updated', completion_date: Date.tomorrow, domain_id: task_1.domain_id }

        Calendar.update_tasks(calendars, @task_params)
      end

      it 'should update_tasks regarding to new task params' do
        expect(Calendar.order(updated_at: :desc).first.title).to include('My Task Updated')
      end
    end
  end
end
