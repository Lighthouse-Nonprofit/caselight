# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D6 — the client-direct reminder is VALUES-LEAN: appointment count +
# wall-clock times only. Task names can carry case context, so they must never appear.
RSpec.describe ClientReminderMailer do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:user)    { create(:user) }
  let!(:client) do
    create(:client, users: [user], given_name: 'Amina',
                    email: 'amina@example.org', notify_consent: true)
  end
  let!(:domain) { create(:domain, name: 'DOMAIN_NAME_SENTINEL') }
  let!(:timed_task) do
    create(:task, client: client, domain: domain, name: 'SENSITIVE_CASE_CONTEXT',
                  completion_date: Time.zone.tomorrow, start_time: '14:30', duration_minutes: 60)
  end
  let!(:all_day_task) do
    create(:task, client: client, domain: domain, name: 'ANOTHER_SENSITIVE_NAME',
                  completion_date: Time.zone.tomorrow)
  end

  let(:mail) { described_class.task_reminder(client, [timed_task, all_day_task]) }

  it 'addresses the client and keeps the subject generic' do
    expect(mail.to).to eq(['amina@example.org'])
    expect(mail.subject).to eq('Reminder: you have an appointment tomorrow')
  end

  it 'is values-lean: count + times only, never task names or domains' do
    body = mail.body.parts.map { |p| p.body.to_s }.join(' ')
    expect(body).to include('2 appointments')
    expect(body).to include('2:30 PM')
    expect(body).not_to include('SENSITIVE_CASE_CONTEXT')
    expect(body).not_to include('ANOTHER_SENSITIVE_NAME')
    expect(body).not_to include(domain.name)
  end
end
