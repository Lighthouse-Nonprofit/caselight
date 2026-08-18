# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require 'tmpdir'
require Rails.root.join('spec', 'support', 'youth_flavor')
require Rails.root.join('spec', 'support', 'casebook_fixture_builder')

# Youth-flavor batch Y5 — the Casebook importer. All fixtures SYNTHETIC (built
# in-test by CasebookFixtureBuilder mirroring the real exports' anatomy):
#   * WorkbookReader: last sheet, meta-row skip, header detect
#   * SubjectClassifier table (incl. diacritic-dropped Casebook subjects)
#   * audit prints aggregates only; import without gates = DRY RUN, zero writes
#   * Applier maps people/cases/notes/providers and is idempotent on re-run
RSpec.describe 'casebook importer' do
  # S1: this spec seeds the youth taxonomy, and those rakes refuse to run on
  # another flavor. WITHOUT this, the guard's `abort` raises SystemExit inside a
  # before hook — an exception RSpec must not rescue — which kills the whole run
  # silently (exit 1, zero reported failures).
  include_context 'youth flavor'
  before(:all) do
    Rake.application.rake_require('tasks/casebook_import', [Rails.root.join('lib').to_s])
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  let(:dir) { Dir.mktmpdir }
  after { FileUtils.remove_entry(dir) if File.exist?(dir) }

  def build_fixtures(dir)
    CasebookFixtureBuilder.build_workbook(File.join(dir, 'people.xlsx'),
      'Filters' => [['junk']],
      'People Data Table' => [
        ['People Reports'],
        ['Person Name', 'Race', 'Hispanic/Latino', 'Sex', 'Age', 'Address', 'City', 'Zip Code',
         'Education', 'Primary Language', 'Poverty Level', 'person_id'],
        ['Maria Test Lopez', 'Other', 'Yes', 'Female', '15', '1 Test St', 'Santa Maria', '93454',
         '', 'Mixteco', 'Below', 'P-001'],
        ['Juan Perez', '', '', 'Male', '16', '', '', '', '', 'Spanish', '', 'P-002'],
        ['Rosa Lopez', '', 'Yes', 'Female', '41', '', '', '', '', 'Spanish', '', 'P-003'],
        ['Sam Twin', '', '', 'Male', '14', '', '', '', '', '', '', 'P-004'],
        ['Sam Twin', '', '', 'Male', '17', '', '', '', '', '', '', 'P-005']
      ])
    CasebookFixtureBuilder.build_workbook(File.join(dir, 'cases.xlsx'),
      'Cases Data Table' => [
        ['Cases Summary'],
        ['Person', 'Person Role', 'Case Name', 'Case Type', 'Case Status', 'Assignee', 'case_id'],
        ['Maria Test Lopez', 'Student', 'Lopez, Maria', 'Direct Services', 'Active', 'Staff One', 'C-01'],
        ['Juan Perez', 'Victim/Survivor', 'Perez, Juan', 'Direct Services', 'Closed', 'Staff Two', 'C-02'],
        ['Rosa Lopez', 'Parent', 'Lopez, Maria', 'Direct Services', 'Active', 'Staff One', 'C-01'],
        ['Sam Twin', 'Student', 'Twin, Sam', 'Direct Services', 'Active', 'Staff One', 'C-03']
      ])
    CasebookFixtureBuilder.build_workbook(File.join(dir, 'notes.xlsx'),
      'Client Notes' => [
        ['Notes Reports'],
        ['Person Name', 'Note Type', 'Subject', 'Narrative', 'Author', 'Contact Start Date', 'Contact Method'],
        ['Maria Test Lopez', 'Client Note', 'Week 2 Joven Noble: Palabra', 'synthetic', 'Staff One', '2025-02-10', 'In Person'],
        ['Maria Test Lopez', 'Client Note', '1:1 check-in', 'synthetic', 'Staff One', '2025-02-17', 'Phone'],
        ['Maria Test Lopez', 'Client Note', 'Week 3', 'synthetic', 'Staff One', '2025-02-24', 'In Person'],
        ['Juan Perez', 'Client Note', 'Navigation', 'synthetic', 'Staff Two', '2025-01-08', 'In Person'],
        ['Juan Perez', 'Client Note', 'Something bespoke', 'synthetic', 'Staff Two', '2025-03-01', 'In Person']
      ])
    CasebookFixtureBuilder.build_workbook(File.join(dir, 'providers.xlsx'),
      'Providers Data Table' => [
        ['Providers Summary'],
        ['Provider Name', 'Provider Status', 'Provider Type', 'provider_id'],
        ['Test Community Org', 'Active', 'CBO', 'PR-01']
      ])
    dir
  end

  describe Casebook::WorkbookReader do
    it 'reads the LAST sheet, skips meta rows, keys rows by the detected header' do
      build_fixtures(dir)
      reader = described_class.new(File.join(dir, 'people.xlsx'))
      rows = reader.rows
      expect(reader.headers).to include('Person Name', 'person_id')
      expect(rows.size).to eq(5)
      expect(rows.first['Person Name']).to eq('Maria Test Lopez')
      expect(rows.first['person_id']).to eq('P-001')
    end
  end

  describe Casebook::SubjectClassifier do
    it 'classifies the service map' do
      expect(described_class.classify('Week 2 Joven Noble: Palabra'))
        .to eq(kind: :session, program: 'El Joven Noble', week: 2, lesson: 'Palabra')
      expect(described_class.classify('Week 10 Cara y Corazon')[:program]).to eq('Cara y Corazón')
      # OCA's dominant real-world forms (from the audit of the actual exports):
      expect(described_class.classify('Joven Noble Group'))
        .to eq(kind: :session, program: 'El Joven Noble', week: nil, lesson: nil)
      expect(described_class.classify('Joven Noble 6: El Otro Yo'))
        .to eq(kind: :session, program: 'El Joven Noble', week: 6, lesson: 'El Otro Yo')
      expect(described_class.classify('Joven Noble 2/11/25')[:week]).to be_nil # a date, not a session
      expect(described_class.classify('Girasol Intro')[:program]).to eq('Girasol')
      expect(described_class.classify('Week 2')).to eq(kind: :bare_session, week: 2)
      expect(described_class.classify('1:1 check-in'))
        .to eq(kind: :tracking, program: '¡Por Vida!', tracking: 'Mentorship Contact')
      expect(described_class.classify('Case Management follow up')[:tracking]).to eq('Case Management Contact')
      expect(described_class.classify('Navigation')[:program]).to eq('Stop The Hate')
      # OCA 2026-08: three named curricula, Session/Clase session formats, and contact types.
      expect(described_class.classify('Cultura Club')[:program]).to eq('Cultura Club')
      expect(described_class.classify('Celebracion')[:program]).to eq('Celebración')
      expect(described_class.classify('Ancestral teachings')[:program]).to eq('Ancestral Teachings')
      expect(described_class.classify('Session 3')).to eq(kind: :bare_session, week: 3)
      expect(described_class.classify('Clase 7-Objectivo')).to include(kind: :bare_session, week: 7)
      expect(described_class.classify('Phone Call')).to eq(kind: :contact, note_type: 'Phone call')
      expect(described_class.classify('Home Visit')).to eq(kind: :contact, note_type: 'Home visit')
      expect(described_class.classify('Parent Phone Call')).to eq(kind: :contact, note_type: 'Parent contact')
      expect(described_class.classify('Ride provided')).to eq(kind: :contact, note_type: 'Transportation')
      expect(described_class.classify('Pre-Assessment')).to eq(kind: :assessment_marker, phase: 'Pre')
      expect(described_class.classify('1-1 Check in: Introduction')[:tracking]).to eq('Mentorship Contact')
      expect(described_class.classify('Referral for Food assistance')[:tracking]).to eq('Navigation / Case Mgmt / Referral')
      expect(described_class.classify('Pre- Assessment and Intake')[:kind]).to eq(:assessment_marker)
      expect(described_class.classify('Something bespoke')).to be_nil
      expect(described_class.classify('')).to be_nil
    end
  end

  describe 'casebook:audit + ungated import' do
    before { build_fixtures(dir) }

    def run_task(name)
      Rake::Task[name].reenable
      out = StringIO.new
      saved = $stdout
      $stdout = out
      Rake::Task[name].invoke
      out.string
    ensure
      $stdout = saved
    end

    it 'audits aggregates only — collision + classifier coverage, never a client name' do
      ENV['CASEBOOK_DIR'] = dir
      output = run_task('casebook:audit')
      expect(output).to include('1 collided name(s) covering 2 People rows')
      expect(output).to include('4/5 classified')
      expect(output).to include('Something bespoke') # unclassified SUBJECTS are listed
      expect(output).to include('Staff One')         # staff names are operational
      expect(output).not_to include('Maria')         # client names never
    ensure
      ENV.delete('CASEBOOK_DIR')
    end

    it 'refuses to write outside the triple gate (DRY RUN)' do
      ENV['CASEBOOK_DIR'] = dir
      ENV['CONFIRM'] = '1' # even with CONFIRM, test env fails the production gate
      expect do
        output = run_task('casebook:import')
        expect(output).to include('DRY RUN')
        expect(output).to include('RAILS_ENV=production')
      end.not_to change(Client, :count)
    ensure
      ENV.delete('CASEBOOK_DIR')
      ENV.delete('CONFIRM')
    end
  end

  describe Casebook::Applier do
    before do
      %w[youth:seed_taxonomy youth:seed_programs youth:seed_quantitative].each do |t|
        ENV['TENANT'] = Apartment::Tenant.current
        Rake::Task[t].reenable
        saved = $stdout
        $stdout = StringIO.new
        Rake::Task[t].invoke
        $stdout = saved
        ENV.delete('TENANT')
      end
      create(:user) if User.none?
      build_fixtures(dir)
    end

    let(:plan) { build_plan(dir) }

    it 'maps people, routes roles, exits closed cases, classifies notes, links the family' do
      Casebook::Applier.new(plan, active_staff: ['Staff One']).apply!

      maria = Client.find_by(given_name: 'Maria Test', family_name: 'Lopez')
      expect(maria).to be_present
      expect(maria.current_address).to eq('1 Test St, Santa Maria, 93454')

      # Graceful collisions (OCA 2026-08): both same-name people are imported as DISTINCT clients
      # (keyed on person_id) rather than silently dropped — the org splits their shared-name records
      # by hand (the audit still lists the collision).
      expect(Client.where(given_name: 'Sam', family_name: 'Twin').count).to eq(2)

      # Student → ¡Por Vida! active; session note implies the cohort enrollment
      pv = maria.client_enrollments.joins(:program_stream).find_by(program_streams: { name: '¡Por Vida!' })
      expect(pv.status).to eq('Active')
      jn = maria.client_enrollments.joins(:program_stream).find_by(program_streams: { name: 'El Joven Noble' })
      sessions = jn.client_enrollment_trackings.ordered
      expect(sessions.map(&:entry_date)).to eq([Date.new(2025, 2, 10), Date.new(2025, 2, 24)])
      expect(sessions.first.properties['Session Number']).to eq('2')
      expect(sessions.first.properties['Session Notes']).to eq('Palabra')
      # the bare "Week 3" note resolved against Maria's SOLE cohort enrollment
      expect(sessions.last.properties['Session Number']).to eq('3')

      # the 1:1 check-in landed as a Mentorship Contact entry with the note date
      mentorship = pv.client_enrollment_trackings.joins(:tracking).find_by(trackings: { name: 'Mentorship Contact' })
      expect(mentorship.entry_date).to eq(Date.new(2025, 2, 17))

      # Victim/Survivor + Closed → STH enrollment exited on the last note date
      juan = Client.find_by(given_name: 'Juan', family_name: 'Perez')
      sth = juan.client_enrollments.joins(:program_stream).find_by(program_streams: { name: 'Stop The Hate' })
      expect(sth.status).to eq('Exited')
      expect(LeaveProgram.find_by(client_enrollment_id: sth.id).exit_date).to eq(Date.new(2025, 3, 1))

      # every note is a ProgressNote; blanks stayed blank
      expect(ProgressNote.where(client_id: maria.id).count).to eq(3)
      expect(maria.date_of_birth).to be_nil

      # Parent → family via KC case (both members linked) AND enrolled as a Cara y Corazón
      # participant (OCA 2026-08: parents are their own participants, not just household members).
      fam = Family.find_by(code: 'CB-C-01')
      # map, not pluck — pluck bypasses the ignore_case encryption reader that
      # restores original case from the original_* sidecar
      expect(fam.clients.map(&:given_name)).to match_array(['Maria Test', 'Rosa'])
      rosa = Client.find_by(given_name: 'Rosa', family_name: 'Lopez')
      expect(rosa.client_enrollments.joins(:program_stream)
                 .where(program_streams: { name: 'Cara y Corazón' })).to be_present

      # staff: assignee active, departed disabled but authorship preserved
      expect(User.find_by(first_name: 'Staff', last_name: 'One').disable).to be(false)
      staff_two = User.find_by(first_name: 'Staff', last_name: 'Two')
      expect(staff_two.disable).to be(true)
      expect(ProgressNote.where(client_id: juan.id).pluck(:user_id).uniq).to eq([staff_two.id])

      expect(Agency.find_by(name: 'Test Community Org')).to be_present
    end

    it 'is idempotent — a second apply creates nothing new' do
      Casebook::Applier.new(plan, active_staff: []).apply!
      counts = [Client.count, ClientEnrollment.count, ClientEnrollmentTracking.count,
                ProgressNote.count, Family.count, Case.count, LeaveProgram.count,
                User.count, Agency.count]
      Casebook::Applier.new(build_plan(dir), active_staff: []).apply!
      expect([Client.count, ClientEnrollment.count, ClientEnrollmentTracking.count,
              ProgressNote.count, Family.count, Case.count, LeaveProgram.count,
              User.count, Agency.count]).to eq(counts)
    end
  end
end
