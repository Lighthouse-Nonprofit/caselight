# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D6 — the SMTP feature flip. Configuring real SES creds + a real
# sender IS the flip; anything less (including the pilot box's literal "nil" strings)
# means client-direct email stays off and behavior is today's staff-only flow.
RSpec.describe ClientMessaging do
  def stub_env(sender:, ses_user:, ses_pass:)
    allow(ENV).to receive(:[]).and_call_original
    allow(ENV).to receive(:[]).with('SENDER_EMAIL').and_return(sender)
    allow(ENV).to receive(:[]).with('AWS_SES_USER_NAME').and_return(ses_user)
    allow(ENV).to receive(:[]).with('AWS_SES_PASSWORD').and_return(ses_pass)
  end

  it 'is disabled with nothing configured' do
    stub_env(sender: nil, ses_user: nil, ses_pass: nil)
    expect(described_class.enabled?).to be(false)
    expect(described_class.sender_email).to be_nil
  end

  it "is disabled for the literal 'nil' strings the pilot box ships" do
    stub_env(sender: 'nil', ses_user: 'nil', ses_pass: 'nil')
    expect(described_class.enabled?).to be(false)
    expect(described_class.sender_email).to be_nil
  end

  it 'is disabled when only the sender is real (no SMTP creds)' do
    stub_env(sender: 'reminders@example.org', ses_user: '', ses_pass: nil)
    expect(described_class.enabled?).to be(false)
    expect(described_class.sender_email).to eq('reminders@example.org') # header hardening still works
  end

  it 'is enabled when sender + both SES creds are real' do
    stub_env(sender: 'reminders@example.org', ses_user: 'AKIA123', ses_pass: 'secret')
    expect(described_class.enabled?).to be(true)
  end
end
