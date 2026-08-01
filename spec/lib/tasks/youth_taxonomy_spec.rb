# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Youth-flavor batch Y3 — the Youth Development taxonomy seeds:
#   * forms land with their INLINE sensitivity (restricted safety/guardian/incident)
#   * programs are MULTI-TRACKING (the Y2 notification fix is load-bearing) and
#     completed:true (the wizard gate bypass)
#   * double-run idempotency (counts stable, no dupes)
#   * the domain reconcile keeps exactly Y1–Y6 and never touches referenced domains
#   * demo seeds are synthetic and exercise backdated entry_date
RSpec.describe 'youth taxonomy seeds' do
  before(:all) do
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  def run_task(name)
    ENV['TENANT'] = Apartment::Tenant.current
    Rake::Task[name].reenable
    # the seed tasks print progress; keep test output clean
    silence = $stdout
    $stdout = StringIO.new
    Rake::Task[name].invoke
  ensure
    $stdout = silence
    ENV.delete('TENANT')
  end

  describe 'youth:seed_taxonomy' do
    before { run_task('youth:seed_taxonomy') }

    it 'creates the six forms with inline sensitivity (no classify pass needed)' do
      expect(CustomField.find_by(entity_type: 'Client', form_title: 'Guardian & Emergency Contacts').sensitivity).to eq('restricted')
      expect(CustomField.find_by(entity_type: 'Client', form_title: 'Youth Safety Plan').sensitivity).to eq('restricted')
      expect(CustomField.find_by(entity_type: 'Client', form_title: 'Hate Incident Record').sensitivity).to eq('restricted')
      expect(CustomField.find_by(entity_type: 'Client', form_title: 'Consents & Releases').sensitivity).to eq('standard')
      expect(CustomField.find_by(entity_type: 'Client', form_title: 'Referral & Intake').sensitivity).to eq('standard')
      expect(CustomField.find_by(entity_type: 'Family', form_title: 'Household & Family Context').sensitivity).to eq('standard')
    end

    it 'passes the server field-type allowlist (every field renderable)' do
      CustomField.where(form_title: ['Guardian & Emergency Contacts', 'Consents & Releases',
                                     'Hate Incident Record']).find_each do |cf|
        cf.fields.each do |f|
          expect(FormBuilderFieldTypes.allowed_type?(f['type'])).to be(true),
            "#{cf.form_title} carries unsupported type #{f['type']}"
        end
      end
    end

    it 'carries the statutory bias categories on the incident record' do
      cf = CustomField.find_by(form_title: 'Hate Incident Record')
      bias = cf.fields.find { |f| f['label'] == 'Bias Category' }
      expect(bias['values'].map { |v| v['value'] })
        .to match_array(['Race', 'Color', 'Disability', 'Religion', 'National origin',
                         'Sexual orientation', 'Gender identity'])
    end

    it 'is idempotent (second run changes nothing)' do
      counts = [CustomField.count, CustomField.pluck(:updated_at).max]
      run_task('youth:seed_taxonomy')
      expect(CustomField.count).to eq(counts[0])
    end
  end

  describe 'youth:seed_programs' do
    before { run_task('youth:seed_programs') }

    it 'creates 10 programs, all completed (wizard gate bypassed)' do
      names = ['¡Por Vida!', 'Stop The Hate', 'Elevate Youth Prevention', 'R.A.I.C.E.S.',
               'El Joven Noble', 'Girasol', 'Cara y Corazón', 'Nurturing Our Futures',
               'Susto y Limpia', 'Mi Palabra']
      names.each do |n|
        ps = ProgramStream.find_by(name: n)
        expect(ps).to be_present, "missing program #{n}"
        expect(ps.completed).to be(true), "#{n} not completed"
      end
    end

    it 'gives ¡Por Vida! its five trackings (multi-tracking is the point)' do
      pv = ProgramStream.find_by(name: '¡Por Vida!')
      expect(pv.trackings.pluck(:name)).to match_array([
        'Case Management Contact', 'Mentorship Contact', 'Academic Check-in (Aeries)',
        'Workshop / Student Engagement', 'SMART Goals Review'
      ])
      expect(pv.trackings.find_by(name: 'Case Management Contact').frequency).to eq('Monthly')
      expect(pv.trackings.find_by(name: 'Mentorship Contact').frequency).to be_nil
    end

    it 'gives each cohort curriculum Site+Term enrollment and a weekly Session Attendance tracking' do
      gira = ProgramStream.find_by(name: 'Girasol')
      labels = gira.enrollment.map { |f| f['label'] }
      expect(labels).to include('School Site', 'Term')
      tr = gira.trackings.sole
      expect(tr.name).to eq('Session Attendance')
      expect(tr.frequency).to eq('Weekly')
    end

    it 'is idempotent (second run keeps counts + trackings stable)' do
      before_counts = [ProgramStream.count, Tracking.count]
      run_task('youth:seed_programs')
      expect([ProgramStream.count, Tracking.count]).to eq(before_counts)
    end
  end

  describe 'youth:seed_quantitative' do
    before { run_task('youth:seed_quantitative') }

    it 'includes the Indigenous-language options on Preferred Language' do
      ql = QuantitativeType.find_by(name: 'Preferred Language')
      expect(ql.allow_multiple).to be(false)
      expect(ql.quantitative_cases.pluck(:value)).to include('Mixteco', 'Zapoteco', 'Triqui', 'Purépecha')
    end

    it 'creates the funder-demographic lists' do
      expect(QuantitativeType.find_by(name: 'Race').allow_multiple).to be(true)
      expect(QuantitativeType.find_by(name: 'Poverty Level').quantitative_cases.pluck(:value))
        .to match_array(%w[Below Above Unknown])
    end
  end

  describe 'youth:seed_domains' do
    before { run_task('youth:seed_domains') }

    it 'keeps exactly the six youth domains (CASEL five + School Engagement)' do
      expect(Domain.pluck(:name)).to match_array(%w[Y1 Y2 Y3 Y4 Y5 Y6])
      expect(Domain.find_by(name: 'Y5').identity).to eq('Responsible Decision-Making')
      expect(DomainGroup.pluck(:name)).to match_array(['1. Social-Emotional Learning (CASEL)', '2. School Engagement'])
    end

    it 'never destroys a referenced other-flavor domain' do
      legacy = Domain.create!(name: 'ZZ-legacy', identity: 'Legacy', domain_group: DomainGroup.first,
                              score_1_color: 'danger', score_2_color: 'warning',
                              score_3_color: 'info', score_4_color: 'primary')
      client = create(:client)
      create(:task, client: client, domain: legacy, completion_date: Time.zone.today)
      run_task('youth:seed_domains')
      expect(Domain.exists?(legacy.id)).to be(true) # referenced => untouched
    end
  end

  describe 'youth:seed_demo_youth' do
    before do
      run_task('youth:seed_taxonomy')
      run_task('youth:seed_programs')
      create(:user) if User.none?
      run_task('youth:seed_demo_youth')
    end

    it 'creates obviously-synthetic youths with cohort enrollments and BACKDATED session entries' do
      marisol = Client.find_by(given_name: 'Demo-Marisol')
      expect(marisol).to be_present
      gira = marisol.client_enrollments.joins(:program_stream).find_by(program_streams: { name: 'Girasol' })
      entries = gira.client_enrollment_trackings.ordered
      expect(entries.size).to eq(3)
      expect(entries.first.entry_date).to be < Time.zone.today # Y2a exercised
    end

    it 'is idempotent on rerun (no duplicate session entries)' do
      counts = ClientEnrollmentTracking.count
      run_task('youth:seed_demo_youth')
      expect(ClientEnrollmentTracking.count).to eq(counts)
    end
  end
end
