# frozen_string_literal: true
require 'rails_helper'

RSpec.describe ProgramStreamDecorator do
  # The program card reads active_enrollment_count three times per card; it is memoized per
  # decorated instance so that is one COUNT, not three (2026-09-26 code pass).
  it 'memoizes active_enrollment_count per decorated instance' do
    program = create(:program_stream)
    create(:client_enrollment, program_stream: program, client: create(:client), status: 'Active')

    decorated = program.decorate
    expect(decorated.active_enrollment_count).to eq(1)

    create(:client_enrollment, program_stream: program, client: create(:client), status: 'Active')
    expect(decorated.active_enrollment_count).to eq(1)              # cached on this instance
    expect(program.reload.decorate.active_enrollment_count).to eq(2) # fresh instance sees the new row
  end
end
