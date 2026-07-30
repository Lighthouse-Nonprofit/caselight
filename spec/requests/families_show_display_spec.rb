# frozen_string_literal: true
require 'rails_helper'

# Investor UX round (2026-07) — families#show display contract:
# - the About grid drops Household ID / State / Household Type / Household Size (the type still
#   badges the header; size duplicated Member Count; ids/geography stay on the edit form + the
#   drawer filters — display-only removal)
# - the header meta drops the "#code" record number (code remains the h1 fallback when unnamed)
# - the members table renders the LEAN column set (given/family name, gender, age, status,
#   programs, case manager) instead of the full ~28-column ClientGrid
# - the Results badge no longer renders translation_missing (families.show.results added)
RSpec.describe 'families#show display contract', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin) { create(:user, roles: 'admin', password: password, password_confirmation: password) }
  let(:province) { Province.find_by(name: 'HouseholdStateSentinel') || Province.create!(name: 'HouseholdStateSentinel') }
  let!(:family) do
    create(:family, name: 'Harbor House', code: 'HH-9', family_type: 'foster',
                    male_adult_count: 1, female_adult_count: 1,
                    male_children_count: 0, female_children_count: 0,
                    province: province)
  end
  let!(:member)      { create(:client, given_name: 'Membery', family_name: 'McMember', state: 'accepted') }
  let!(:member_case) { create(:case, case_type: 'FC', client: member, family: family) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  it 'renders the lean household page: no id/geo/type/size rows, no header slug, lean member columns' do
    get family_path(family)
    expect(response).to have_http_status(:ok)
    body = response.body

    # still there: identity, the kept About rows, the type badge in the header
    expect(body).to include('Harbor House')
    expect(body).to include('About Family')
    expect(body).to include('Member Count')
    expect(body).to include('Sponsor Household')

    # gone: the four About rows (Household ID doubles as the family_id grid header — both gone),
    # the "#HH-9" header slug, and the missing-translation badge
    expect(body).not_to include('Household ID')
    expect(body).not_to include('Household Size')
    expect(body).not_to include("##{family.code}")
    expect(body).not_to match(/>State</)
    # follow-up: the geographic value itself left EVERY household display (header meta too)
    expect(body).not_to include('HouseholdStateSentinel')
    expect(body).not_to include('translation_missing')

    # lean members table: case-manager column in, full-grid columns out, member row renders
    expect(body).to include('Membery')
    expect(body).to include('Case Manager')
    expect(body).not_to include('Date of Birth')
  end
end
