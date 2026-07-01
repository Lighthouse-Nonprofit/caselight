# frozen_string_literal: true
require 'rails_helper'

# Card-grid redesign security contract. The individuals + families index cards must render ONLY
# core, non-sensitivity-gated identity/program fields — never a Phase-5.3-masked custom-field /
# assessment / domain value or the restricted FORM TITLE. They must also render the authorized+
# paginated card list and keep the filter form + pagination. NON-VACUOUS: we sign in as ADMIN,
# who CAN see the restricted value on the detail/show page; its absence from the card body
# therefore proves the card omits custom-field data (not merely that the record is out of scope).
# Fixture conventions mirror spec/requests/sensitive_field_masking_cfp_spec.rb.
RSpec.describe 'Card-grid index security', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }
  let(:admin)    { create(:user, roles: 'admin', password: password, password_confirmation: password) }

  before { post user_session_path, params: { user: { email: admin.email, password: password } } }

  describe 'clients#index cards' do
    let!(:client) { create(:client, given_name: 'Cardy', family_name: 'McCardface', status: 'Referred') }

    # A RESTRICTED custom form filled with a sentinel value. The card must NOT emit this value or
    # the form title (the sensitivity-gated custom-field data lives only on the detail/show page,
    # which masks it). Same factory shape as the Unit-6 masking specs.
    let!(:restricted_cf) do
      create(:custom_field, entity_type: 'Client', form_title: 'CardSpec Restricted Immigration',
             sensitivity: 'restricted', fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
    end
    let!(:res_prop) do
      create(:custom_field_property, custom_field: restricted_cf, custom_formable: client,
             properties: { 'Diagnosis' => 'CARD_SENTINEL_DO_NOT_LEAK' })
    end

    it 'renders core fields, the card list landmark, filter form, pagination + sort — but no gated value' do
      get clients_path
      expect(response).to have_http_status(:ok)
      body = response.body

      # (b) core fields present on the card
      expect(body).to include('Cardy McCardface')
      expect(body).to match(/record-card__status/)
      expect(body).to match(/record-card__avatar/)
      # (a) card list landmark exists (iterates @client_grid.assets = accessible_by + paginated)
      expect(body).to match(/class=["'][^"']*\brecord-cards\b/)
      # (c) NO sensitivity-gated custom-field value on the card, and no dynamic form title column
      expect(body).not_to include('CARD_SENTINEL_DO_NOT_LEAK')
      expect(body).not_to include('CardSpec Restricted Immigration')
      # (d) filter form + pagination + sort survive
      expect(body).to include('client-search-form')
      expect(body).to match(/grid-form/)
      expect(body).to match(/name=["']client_grid\[order\]["']/)
    end
  end

  describe 'families#index cards' do
    let!(:family) do
      create(:family, name: 'Harbor House', code: 'HH-1', family_type: 'kinship',
             male_adult_count: 1, female_adult_count: 1, male_children_count: 2, female_children_count: 0,
             case_history: 'FAMILY_SENTINEL_DO_NOT_LEAK')
    end

    it 'renders core household fields + landmark + filter form + pagination + sort, but no encrypted narrative' do
      get families_path
      expect(response).to have_http_status(:ok)
      body = response.body

      # (b) core household fields
      expect(body).to include('Harbor House')
      expect(body).to include('HH-1')
      expect(body).to match(/record-card__tag--type/)   # family-type chip
      expect(body).to match(/4 member/)                 # member_count = 1+1+2+0
      # (a) landmark
      expect(body).to match(/class=["'][^"']*\brecord-cards\b/)
      # (c) no encrypted case_history narrative on the card
      expect(body).not_to include('FAMILY_SENTINEL_DO_NOT_LEAK')
      # (d) filter form + pagination + sort survive
      expect(body).to include('family-search-form')
      expect(body).to match(/name=["']family_grid\[order\]["']/)
    end
  end
end
