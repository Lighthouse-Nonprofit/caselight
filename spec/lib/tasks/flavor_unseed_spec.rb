# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# Bifurcation cleanup (flavor:unseed_*) — the engine behind switch-flavor.sh:
#   * removes exactly the target flavor's taxonomy + demo records
#   * leaves the other flavor untouched, and the active flavor's domain
#     reconcile sweeps the foreign domains once their references die
#   * layered guards: CONFIRM_UNSEED, never-the-active-flavor, real-data aborts
RSpec.describe 'flavor unseed' do
  # S1: the youth seed rakes refuse on another flavor, but THIS spec asserts on
  # the active flavor itself (unseeding the active flavor must be refused), so a
  # blanket youth stub would invert its meaning. Instead the flavor is dynamic:
  # 'youth' only while seed_youth_side is planting the taxonomy to be removed.
  before do
    allow(Rails.application.config.x).to receive(:flavor) { @flavor_override || 'resettlement' }
  end

  before(:all) do
    %w[flavor flavor_unseed youth_taxonomy slo4home_taxonomy sensitivity_classification].each do |f|
      Rake.application.rake_require("tasks/#{f}", [Rails.root.join('lib').to_s])
    end
    Rake::Task.define_task(:environment)
  end

  def run_task(name, env = {})
    ENV['TENANT'] = Apartment::Tenant.current
    env.each { |k, v| ENV[k] = v }
    Rake::Task[name].reenable
    saved = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke
  ensure
    $stdout = saved
    ENV.delete('TENANT')
    env.each_key { |k| ENV.delete(k) }
  end

  def seed_youth_side
    create(:user) if User.none?
    @flavor_override = 'youth'
    %w[youth:seed_taxonomy youth:seed_programs youth:seed_quantitative youth:seed_domains
       youth:seed_demo_youth].each { |t| run_task(t) }
  ensure
    @flavor_override = nil # back to resettlement for the unseed assertions
  end

  describe 'guards' do
    it 'refuses without CONFIRM_UNSEED=1' do
      expect { run_task('flavor:unseed_youth') }
        .to raise_error(SystemExit, /CONFIRM_UNSEED/)
    end

    it 'refuses to unseed the ACTIVE flavor' do
      # test env runs FLAVOR-unset = resettlement
      expect { run_task('flavor:unseed_resettlement', 'CONFIRM_UNSEED' => '1') }
        .to raise_error(SystemExit, /ACTIVE flavor/)
    end

    it 'aborts untouched when a non-demo client is enrolled in the flavor' do
      seed_youth_side
      outsider = create(:client, given_name: 'Real', family_name: 'Person', state: 'accepted')
      girasol = ProgramStream.find_by(name: 'Girasol')
      ClientEnrollment.create!(client: outsider, program_stream: girasol, status: 'Active',
                               enrollment_date: Time.zone.today,
                               properties: { 'School Site' => 'Delta HS', 'Term' => 'Fall 25' })
      expect { run_task('flavor:unseed_youth', 'CONFIRM_UNSEED' => '1') }
        .to raise_error(SystemExit, /real data/)
      expect(ProgramStream.where(name: 'Girasol')).to exist
      expect(CustomField.find_by(form_title: 'Youth Safety Plan')).to be_present
    end
  end

  describe 'flavor:unseed_youth (on a resettlement server)' do
    before { seed_youth_side }

    it 'removes the youth taxonomy + demo and leaves resettlement intact' do
      # resettlement fixtures to prove non-interference
      run_task('slo4home:seed_programs')
      run_task('slo4home:seed_domains')

      expect(Client.find_by(given_name: 'Demo-Marisol')).to be_present
      run_task('flavor:unseed_youth', 'CONFIRM_UNSEED' => '1')

      # youth gone: demo, programs, forms, lists, domains
      expect(Client.find_by(given_name: 'Demo-Marisol')).to be_nil
      expect(Family.where("code LIKE 'OCA-DEMO-%'")).to be_empty
      expect(ProgramStream.where(name: ['¡Por Vida!', 'Girasol', 'Mi Palabra'])).to be_empty
      expect(CustomField.where(form_title: ['Youth Safety Plan', 'Hate Incident Record'])).to be_empty
      expect(QuantitativeType.where(name: ['Preferred Language', 'School Site'])).to be_empty
      expect(Domain.where(name: %w[Y1 Y2 Y3 Y4 Y5 Y6])).to be_empty

      # resettlement untouched (programs + its full domain set)
      expect(ProgramStream.where(name: %w[Housing Employment]).count).to eq(2)
      expect(Domain.count).to be >= 12
      expect(ClientEnrollmentTracking.count).to eq(0) # the demo session entries died with their youths
    end

    it 'is idempotent — a second run removes nothing and does not raise' do
      run_task('flavor:unseed_youth', 'CONFIRM_UNSEED' => '1')
      expect { run_task('flavor:unseed_youth', 'CONFIRM_UNSEED' => '1') }.not_to raise_error
    end
  end
end
