# frozen_string_literal: true
require 'rails_helper'

RSpec.describe ClientsHelper, type: :helper do
  describe '#merged_address' do
    # Cambodia-era hardcode removed 2026-08: this is a US deployment, so the address must not append
    # "Cambodia". It shows only the parts the record carries (+ province/State).
    before { allow(helper).to receive(:locale).and_return(:en) }

    it 'does not append Cambodia' do
      client = build(:client, house_number: '123', street_number: 'Elm St')
      address = helper.merged_address(client)
      expect(address).not_to match(/cambodia/i)
      expect(address).to include('123') # real parts still shown
    end

    it 'shows the province/State (last segment) without a trailing country' do
      client = build(:client, house_number: '9', province: build(:province, name: 'CA / California'))
      address = helper.merged_address(client)
      expect(address).to include('California')
      expect(address).not_to match(/cambodia/i)
      expect(address).not_to end_with('California, ') # nothing appended after the province
    end
  end
end
