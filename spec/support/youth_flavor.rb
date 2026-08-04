# frozen_string_literal: true

# S1 — the test posture is FLAVOR-unset (= resettlement), but the youth
# surfaces (schools routes, youth seed rakes) are LOCKED to the youth flavor.
# Specs that exercise them stub config.x.flavor; route constraints and the rake
# guard both read it at call time, so the stub is enough — no boot-time env
# juggling. `include_context 'youth flavor'` (or call as_youth_flavor!).
RSpec.shared_context 'youth flavor' do
  before { allow(Rails.application.config.x).to receive(:flavor).and_return('youth') }
end

module YouthFlavorHelper
  def as_youth_flavor!
    allow(Rails.application.config.x).to receive(:flavor).and_return('youth')
  end
end

RSpec.configure do |config|
  config.include YouthFlavorHelper
end
