# frozen_string_literal: true
require 'rails_helper'

# config/initializers/filter_parameter_logging.rb — pins that the request-log redaction covers the
# credential-shaped params the app actually permits (users' pin_number; the WebAuthn credential
# blob) alongside the long-standing password/token/PII keys.
RSpec.describe 'filter_parameters' do
  let(:filter) { ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters) }

  it 'redacts pin_number and the passkey credential blob' do
    filtered = filter.filter('pin_number' => '1234', 'credential' => { 'id' => 'abc', 'response' => 'x' },
                             'user' => { 'password' => 'hunter2', 'otp_attempt' => '000000' })

    expect(filtered['pin_number']).to eq('[FILTERED]')
    expect(filtered['credential']).to eq('[FILTERED]')
    expect(filtered['user']['password']).to eq('[FILTERED]')
    expect(filtered['user']['otp_attempt']).to eq('[FILTERED]')
  end

  it 'does not over-match ordinary keys' do
    expect(filter.filter('mapping' => 'kept', 'name' => 'kept')).to eq('mapping' => 'kept', 'name' => 'kept')
  end
end
