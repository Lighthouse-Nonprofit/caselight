require 'spec_helper'

# Serializer attribute allowlist lock (PII / credential re-add guard) — POAM-016 regression class.
#
# The per-serializer specs (client_serializer_spec, case_serializer_spec, family_serializer_spec,
# user_serializer_spec) assert individual attributes with positive `have_json_path` only. That style
# proves a field IS present but NEVER proves the set is *closed*: silently re-adding pin_number under
# a new name, an SSN / A-number, or a ledger of carer PII would ship green because nothing pins the
# EXACT attribute set. These serializers carry Tier 1-5 encrypted PII (names, addresses, DOB) and
# credential-adjacent staff data, so the exposed surface must be an allowlist, not a denylist.
#
# Each example below locks `Serializer._attributes` (in AMS 0.10, the declared attribute keys) to a
# frozen allowlist with `match_array` (order-independent, membership-exact). Adding OR removing any
# attribute now fails here, forcing the change to be a deliberate, reviewed edit to this list — which
# is exactly the review gate POAM-016 was created to enforce.
RSpec.describe 'Serializer attribute allowlist lock', type: :serializer do
  it 'UserSerializer exposes exactly its frozen allowlist (re-adding pin_number / any credential attr fails)' do
    allowlist = %i[
      id first_name last_name email roles mobile date_of_birth
      archived admin manager_id clients
    ].freeze

    expect(UserSerializer._attributes).to match_array(allowlist)
    # POAM-016 sentinel: the staff credential-adjacent secret must never re-enter the API surface.
    expect(UserSerializer._attributes).not_to include(:pin_number)
  end

  it 'ClientSerializer exposes exactly its frozen allowlist (a new PII attribute must be added deliberately)' do
    allowlist = %i[
      id given_name family_name gender code status date_of_birth grade
      current_province local_given_name local_family_name kid_id donor
      current_address house_number street_number village commune district
      completed birth_province time_in_care initial_referral_date referral_source
      referral_phone live_with id_poor received_by followed_up_by follow_up_date
      school_name school_grade has_been_in_orphanage able_state
      has_been_in_government_care relevant_referral_information case_workers
      agencies state rejected_note emergency_care foster_care kinship_care
      organization additional_form tasks assessments case_notes quantitative_cases
      program_streams add_forms
    ].freeze

    expect(ClientSerializer._attributes).to match_array(allowlist)
  end

  it 'CaseSerializer exposes exactly its frozen allowlist (guards silent carer/exit PII additions, incl. embedded-case payloads)' do
    # CaseSerializer is embedded into ClientSerializer (#emergency_care/#foster_care/#kinship_care) and
    # FamilySerializer (#clients -> current_case), so any new carer_* / exit_* field leaks through those
    # payloads too — this lock is the single chokepoint for all of them.
    allowlist = %i[
      id start_date carer_names carer_address carer_phone_number support_amount
      support_note case_type exited exit_date exit_note family partner province
      created_at updated_at family_preservation status placement_date
      initial_assessment_date case_length case_conference_date time_in_care
      exited_from_cif current
    ].freeze

    expect(CaseSerializer._attributes).to match_array(allowlist)
  end

  it 'FamilySerializer exposes exactly its frozen top-level allowlist' do
    allowlist = %i[
      id name code case_history caregiver_information significant_family_member_count
      household_income dependable_income female_children_count male_children_count
      female_adult_count male_adult_count family_type contract_date address province
      clients
    ].freeze

    expect(FamilySerializer._attributes).to match_array(allowlist)
  end
end
