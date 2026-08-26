# frozen_string_literal: true
require 'rails_helper'
require Rails.root.join('spec', 'support', 'youth_flavor')

# OCA feedback 2026-08-26 — Araceli: the org dashboard only showed cumulative/historical totals.
# She needs "how are we doing this term, for this cohort?" at a glance, to answer school-site
# contacts and district reporting without exporting.
#
# Both filters are plain GET params so the page stays CSP-safe and a filtered dashboard is a
# shareable URL. Period handling reuses Reports::Period rather than new date maths.
RSpec.describe 'Org dashboard — period + cohort filters', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin) { create(:user, roles: 'admin') }
  before { sign_in admin }

  # A cohort is a ProgramStream carrying a "Session Attendance" tracking (Cohorts.programs).
  def cohort_program(name)
    ps = create(:program_stream, name: name, quantity: nil)
    create(:tracking, program_stream: ps, name: Cohorts::SESSION_TRACKING)
    ps
  end

  def enrol(client, program)
    create(:client_enrollment, client: client, program_stream: program, status: 'Active',
                               properties: { 'e-mail' => 'a@b.test', 'age' => '3',
                                             'description' => 'x' })
  end

  describe 'the page renders' do
    it 'shows the period picker and a cohort chip row' do
      cohort_program('Girasol')
      get dashboards_path

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('dashboard-period')
      expect(response.body).to include('filter-chips__chip')
      expect(response.body).to include('Girasol')
    end

    it 'marks the selected cohort chip active and sets aria-current' do
      gira = cohort_program('Girasol')
      get dashboards_path(cohort_id: gira.id)

      expect(response).to have_http_status(:ok)
      chips = response.body[/<ul class="filter-chips.*?<\/ul>/m]
      expect(chips).to include('filter-chips__chip--active')
      expect(chips).to include('aria-current')
    end

    it 'falls back to a valid period when the param is tampered with' do
      # Period.resolve validates the preset against the allowlist; a bad value must not raise.
      get dashboards_path(period: 'not_a_preset|garbage|garbage')
      expect(response).to have_http_status(:ok)
    end

    it 'ignores an unknown cohort_id rather than erroring' do
      get dashboards_path(cohort_id: 999_999)
      expect(response).to have_http_status(:ok)
    end
  end

  describe 'cohort filtering' do
    it 'narrows the individual count to the selected cohort' do
      gira  = cohort_program('Girasol')
      other = cohort_program('El Joven Noble')

      in_gira = create_list(:client, 2, state: 'accepted')
      in_gira.each { |c| enrol(c, gira) }
      enrol(create(:client, state: 'accepted'), other)

      get dashboards_path
      unfiltered = controller_ivar(:@clients_total)

      get dashboards_path(cohort_id: gira.id)
      filtered = controller_ivar(:@clients_total)

      expect(unfiltered).to be >= 3
      expect(filtered).to eq(2)
    end
  end

  describe 'period filtering' do
    it 'counts check-ins by service date within the period, not lifetime' do
      gira   = cohort_program('Girasol')
      client = create(:client, state: 'accepted')
      ce     = enrol(client, gira)
      tracking = gira.trackings.first

      create(:client_enrollment_tracking, client_enrollment: ce, tracking: tracking,
                                          entry_date: Time.zone.today)
      create(:client_enrollment_tracking, client_enrollment: ce, tracking: tracking,
                                          entry_date: 3.years.ago.to_date)

      get dashboards_path(period: "custom", from: 30.days.ago.to_date.iso8601,
                          to: Time.zone.today.iso8601)

      expect(response).to have_http_status(:ok)
      expect(controller_ivar(:@checkins_in_period)).to eq(1)
    end
  end

  # The org tiles used to call Family.count / Client.count directly, bypassing the ability layer.
  describe 'ability scoping' do
    it 'counts individuals through accessible_by, not a raw Client.count' do
      create_list(:client, 2, state: 'accepted')
      get dashboards_path

      expect(controller_ivar(:@clients_total))
        .to eq(Client.accessible_by(Ability.new(admin)).count)
    end
  end

  def controller_ivar(name)
    controller.instance_variable_get(name)
  end
end
