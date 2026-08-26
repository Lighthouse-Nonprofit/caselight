# frozen_string_literal: true
require 'rails_helper'

# OCA 2026-08-26 — this policy is what actually gates an enrollment save, and it had NO coverage
# at all (there was no spec/policies directory). It was also the site of the bug Araceli reported:
# both of its gates keyed on (client, program) across the program's entire lifetime, so
#
#   * a youth Active in a PRIOR cohort could never be enrolled into a new one, and
#   * `quantity` counted every client ever active in the program — and youth:seed_programs stamped
#     quantity: 30 on every program, which had already hard-blocked El Joven Noble (164 active),
#     Girasol (51), Nurturing Our Futures (41) and Celebración (38) on the OCA box.
#
# Both gates are now scoped to the cohort being enrolled into, where the cohort key is derived from
# the enrollment form's Site + Term. A blank key is the single default bucket — which is where the
# historic Casebook import lives, so imported history can never block a real new cohort.
RSpec.describe ClientEnrollmentPolicy, type: :policy do
  let(:user)    { create(:user, roles: 'admin') }
  let(:program) { create(:program_stream, quantity: nil) }

  # The :program_stream factory's enrollment form marks e-mail/age/description required, and
  # CustomFormPresentValidator enforces that against `properties` — so cohort keys have to be
  # merged into those defaults, not substituted for them.
  REQUIRED_FORM_VALUES = { 'e-mail' => 'test@example.com', 'age' => '3',
                           'description' => 'this is testing' }.freeze

  # The cohort key is derived from properties, so this is how a caller "picks" a cohort.
  def enrollment_in(cohort_site, client:, program_stream: program, status: 'Active', persist: true)
    cohort = cohort_site.nil? ? {} : { 'Site' => cohort_site, 'Term' => 'Fall 26' }
    attrs = { client: client, program_stream: program_stream, status: status,
              properties: REQUIRED_FORM_VALUES.merge(cohort) }
    persist ? create(:client_enrollment, **attrs) : build(:client_enrollment, **attrs)
  end

  def allowed?(record)
    described_class.new(user, record).create?
  end

  describe 'cohort identity' do
    it 'derives the key from Site + Term and persists it on save' do
      ce = enrollment_in('Delta HS', client: create(:client))
      expect(ce.cohort).to eq("Delta HS · Fall 26")
    end

    it 'treats a missing Site/Term as the single default bucket' do
      ce = enrollment_in(nil, client: create(:client))
      expect(ce.cohort).to eq('')
    end

    it 'shares one key format with the Casebook importer' do
      expect(ClientEnrollment.cohort_key('Delta HS', 'Fall 26')).to eq("Delta HS · Fall 26")
    end
  end

  describe 'enrolling into a DIFFERENT cohort of the same program' do
    let(:client) { create(:client) }

    # This is the regression Araceli hit: still Active in last term's cohort, refused for this one.
    it 'is allowed while Active in a prior cohort' do
      enrollment_in('Delta HS', client: client)
      expect(allowed?(enrollment_in('Righetti HS', client: client, persist: false))).to be true
    end

    it 'is refused while already Active in the SAME cohort' do
      enrollment_in('Delta HS', client: client)
      expect(allowed?(enrollment_in('Delta HS', client: client, persist: false))).to be false
    end

    it 'is allowed again once the same cohort has been Exited' do
      enrollment_in('Delta HS', client: client, status: 'Exited')
      expect(allowed?(enrollment_in('Delta HS', client: client, persist: false))).to be true
    end

    it 'is not blocked by historic import rows sitting in the default bucket' do
      enrollment_in(nil, client: client) # blank-cohort Casebook history, still 'Active'
      expect(allowed?(enrollment_in('Delta HS', client: client, persist: false))).to be true
    end
  end

  describe 'capacity' do
    let(:capped) { create(:program_stream, quantity: 2) }

    it 'is unlimited when quantity is blank' do
      3.times { enrollment_in('Delta HS', client: create(:client), program_stream: program) }
      newcomer = enrollment_in('Delta HS', client: create(:client), program_stream: program, persist: false)
      expect(allowed?(newcomer)).to be true
    end

    it 'counts only the cohort being enrolled into, not the program lifetime' do
      2.times { enrollment_in('Delta HS', client: create(:client), program_stream: capped) }

      full  = enrollment_in('Delta HS', client: create(:client), program_stream: capped, persist: false)
      other = enrollment_in('Righetti HS', client: create(:client), program_stream: capped, persist: false)

      expect(allowed?(full)).to be false   # this cohort is genuinely full
      expect(allowed?(other)).to be true   # a different cohort is not
    end

    it 'does not count blank-status historic import clients toward the cap' do
      2.times do
        historic = create(:client)
        enrollment_in('Delta HS', client: historic, program_stream: capped)
        # Blank the status AFTER enrolling: ClientEnrollment's after_create :set_client_status
        # would otherwise overwrite it. This is also the real order of events — the Casebook
        # import creates the enrollment history and leaves the client status blank.
        historic.update_column(:status, '')
      end

      newcomer = enrollment_in('Delta HS', client: create(:client), program_stream: capped, persist: false)
      expect(allowed?(newcomer)).to be true
    end

    it 'agrees with the decorator badge that the UI shows' do
      2.times { enrollment_in('Delta HS', client: create(:client), program_stream: capped) }
      decorated = ProgramStreamDecorator.new(capped)

      expect(decorated.maximum_client?('Delta HS · Fall 26')).to be true
      expect(allowed?(enrollment_in('Delta HS', client: create(:client), program_stream: capped, persist: false))).to be false
    end
  end

  # ProgramStream#enroll? drives the Re-enroll button; the policy drives the save. They used to
  # disagree by construction (.first vs .last), so the button could appear and then bounce you.
  describe 'ProgramStream#enroll? agrees with the policy' do
    let(:client) { create(:client) }

    it 'both refuse a client Active in the cohort' do
      enrollment_in(nil, client: client)
      expect(program.enroll?(client)).to be false
      expect(allowed?(enrollment_in(nil, client: client, persist: false))).to be false
    end

    it 'both allow a client whose NEWEST enrollment in the cohort is Exited' do
      enrollment_in(nil, client: client, status: 'Exited')
      enrollment_in(nil, client: client, status: 'Active').update!(status: 'Exited')

      expect(program.enroll?(client)).to be true
      expect(allowed?(enrollment_in(nil, client: client, persist: false))).to be true
    end

    it 'both refuse when the newest enrollment is Active even though an older one Exited' do
      enrollment_in(nil, client: client, status: 'Exited')
      enrollment_in(nil, client: client, status: 'Active')

      expect(program.enroll?(client)).to be false
      expect(allowed?(enrollment_in(nil, client: client, persist: false))).to be false
    end
  end
end
