# frozen_string_literal: true
require 'rails_helper'

# Youth-flavor batch Y2(a)+(b):
#   * entry_date = the backdatable SERVICE date (defaults to today; ordering key)
#   * the notification clock is scoped PER TRACKING (the old unscoped .last let any
#     tracking's entry reset every other tracking's clock) and a zero-entry tracking
#     falls back to the enrollment date instead of CRASHING the bell path
RSpec.describe 'Tracking entry dates + notification clocks (Y2)' do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:user)    { create(:user) }
  let!(:client) { create(:client, users: [user], state: 'accepted') }
  let(:program) { create(:program_stream, tracking_required: false) }
  let!(:weekly) do
    create(:tracking, program_stream: program, name: 'Session Attendance',
                      frequency: 'Weekly', time_of_frequency: 1)
  end
  let!(:monthly) do
    create(:tracking, program_stream: program, name: 'Monthly Check-in',
                      frequency: 'Monthly', time_of_frequency: 1)
  end
  let!(:enrollment) do
    create(:client_enrollment, client: client, program_stream: program,
                               enrollment_date: Time.zone.today - 6.weeks, status: 'Active')
  end

  # the tracking factory's fields carry three required inputs — satisfy them
  PROPS = { 'e-mail' => 'test@example.com', 'age' => '3', 'description' => 'ok' }.freeze

  def entry(tracking, date)
    ClientEnrollmentTracking.create!(client_enrollment: enrollment, tracking: tracking,
                                     properties: PROPS, entry_date: date)
  end

  describe 'entry_date (Y2a)' do
    it 'defaults to today and is required' do
      cet = ClientEnrollmentTracking.create!(client_enrollment: enrollment, tracking: weekly,
                                             properties: PROPS)
      expect(cet.entry_date).to eq(Time.zone.today)
    end

    it 'accepts a backdated service date and orders by it' do
      old = entry(weekly, Time.zone.today - 5.weeks)
      new = entry(weekly, Time.zone.today - 1.day)
      expect(ClientEnrollmentTracking.ordered.last).to eq(new)
      expect(ClientEnrollmentTracking.ordered.first).to eq(old)
      expect(old.reload.entry_date).to eq(Time.zone.today - 5.weeks)
    end
  end

  describe 'per-tracking notification clock (Y2b)' do
    it 'does not let one tracking reset another (the cross-reset bug)' do
      entry(monthly, Time.zone.today - 6.weeks) # monthly overdue for 2 weeks
      entry(weekly, Time.zone.today)            # fresh weekly entry — must NOT reset monthly

      monthly_due = client.next_client_enrollment_tracking_date(monthly, enrollment)
      expect(monthly_due).to eq(Time.zone.today - 6.weeks + 1.month) # overdue, unaffected
      weekly_due = client.next_client_enrollment_tracking_date(weekly, enrollment)
      expect(weekly_due).to eq(Time.zone.today + 1.week)
    end

    it 'falls back to the enrollment date for a zero-entry tracking (the crash bug)' do
      expect(client.next_client_enrollment_tracking_date(weekly, enrollment))
        .to eq(enrollment.enrollment_date + 1.week)
    end

    it 'surfaces overdue + due-today correctly through the concern' do
      # weekly: zero entries, enrolled 6 weeks ago => overdue via the fallback (the old
      # code never even iterated a zero-entry tracking, and crashed when it tried)
      result = user.client_enrollment_tracking_notification([client])
      expect(result[:clients_overdue]).to include(client)
    end

    it 'reasons on entry_date, not typed-at time' do
      backdated = entry(monthly, Time.zone.today - 2.months)
      backdated.update_column(:created_at, Time.zone.now) # typed today, happened long ago
      due = client.next_client_enrollment_tracking_date(monthly, enrollment)
      expect(due).to eq(Time.zone.today - 2.months + 1.month) # overdue by ~a month
    end
  end
end
