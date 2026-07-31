# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D6 — the daily due-tomorrow cron rider:
#   * flip OFF (default) => today's staff-only behavior EXACTLY (zero client mails)
#   * flip ON  => consented clients with an email get ONE values-lean reminder;
#     no consent / no email => nothing; staff mail unchanged either way
RSpec.describe 'Task.upcoming_incomplete_tasks client reminders (D6)' do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:user)    { create(:user) }
  let!(:domain) { create(:domain) }

  let!(:consented) do
    create(:client, users: [user], email: 'consented@example.org', notify_consent: true)
  end
  let!(:no_consent) do
    create(:client, users: [user], email: 'silent@example.org', notify_consent: false)
  end
  let!(:no_email) { create(:client, users: [user], notify_consent: true) }

  before do
    [consented, no_consent, no_email].each do |client|
      create(:task, client: client, domain: domain, completion_date: Time.zone.tomorrow)
    end
    allow(CaseWorkerMailer).to receive(:tasks_due_tomorrow_of)
      .and_return(double(deliver_now: true))
  end

  def stub_flip(on)
    allow(ClientMessaging).to receive(:enabled?).and_return(on)
  end

  it 'sends nothing to clients while the flip is off (the default)' do
    stub_flip(false)
    expect(ClientReminderMailer).not_to receive(:task_reminder)
    Task.upcoming_incomplete_tasks
    expect(CaseWorkerMailer).to have_received(:tasks_due_tomorrow_of).at_least(:once) # staff flow intact
  end

  it 'mails exactly the consented-with-email clients when the flip is on' do
    stub_flip(true)
    delivered = []
    allow(ClientReminderMailer).to receive(:task_reminder) do |client, tasks|
      delivered << [client.id, tasks.size]
      double(deliver_now: true)
    end

    Task.upcoming_incomplete_tasks

    expect(delivered).to eq([[consented.id, 1]])
    expect(CaseWorkerMailer).to have_received(:tasks_due_tomorrow_of).at_least(:once)
  end
end
