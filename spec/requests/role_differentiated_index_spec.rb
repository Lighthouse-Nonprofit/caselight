# frozen_string_literal: true
require 'rails_helper'

RSpec.describe 'Workstream A — role-differentiated index views', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'clients#index' do
    let!(:client) { create(:client, given_name: 'Cardy', family_name: 'McCardface', status: 'Referred') }

    let!(:restricted_cf) do
      create(:custom_field, entity_type: 'Client', form_title: 'WsA Restricted Immigration',
             sensitivity: 'restricted', fields: [{ 'type' => 'text', 'label' => 'Diagnosis' }])
    end
    let!(:res_prop) do
      create(:custom_field_property, custom_field: restricted_cf, custom_formable: client,
             properties: { 'Diagnosis' => 'GRID_SENTINEL_DO_NOT_LEAK' })
    end

    context 'as admin (limited grid)' do
      let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
      before { sign_in_as(admin) }

      it 'renders the LIMITED GRID with core fields only — and no sensitivity-gated value' do
        get clients_path
        expect(response).to have_http_status(:ok)
        body = response.body

        expect(body).to match(/class=["'][^"']*\brecord-grid__table\b/)
        expect(body).not_to match(/class=["'][^"']*\brecord-cards\b/)

        expect(body).to include('Cardy McCardface')
        expect(body).to match(/record-grid__name-link/)
        expect(body).to match(/record-grid__status/)
        expect(body).to include(client_path(client))

        expect(body).not_to include('GRID_SENTINEL_DO_NOT_LEAK')
        expect(body).not_to include('WsA Restricted Immigration')

        expect(body).to include('client-search-form')
        expect(body).to match(/grid-form/)
        expect(body).to match(/name=["']client_grid\[order\]["']/)
      end
    end

    context 'as strategic_overviewer (limited grid)' do
      let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }
      before { sign_in_as(overviewer) }

      it 'also renders the LIMITED GRID, not the card grid' do
        get clients_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/class=["'][^"']*\brecord-grid__table\b/)
        expect(response.body).not_to match(/class=["'][^"']*\brecord-cards\b/)
      end
    end

    context 'as case_worker (card grid)' do
      let(:worker) { create(:user, :case_worker, password: password, password_confirmation: password) }
      before { client.users << worker; sign_in_as(worker) }

      it 'renders the CARD grid, not the limited grid' do
        get clients_path
        expect(response).to have_http_status(:ok)
        body = response.body
        expect(body).to match(/class=["'][^"']*\brecord-cards\b/)
        expect(body).not_to match(/class=["'][^"']*\brecord-grid__table\b/)
        expect(body).to include('Cardy McCardface')
      end
    end
  end

  describe 'families#index' do
    let!(:family) do
      create(:family, name: 'Harbor House', code: 'HH-1', family_type: 'kinship',
             male_adult_count: 1, female_adult_count: 1, male_children_count: 2, female_children_count: 0,
             case_history: 'FAMILY_SENTINEL_DO_NOT_LEAK')
    end
    let!(:member) { create(:client, given_name: 'Mem', family_name: 'Ber') }
    let!(:kase)   { create(:case, family: family, client: member) }

    context 'as admin (limited grid)' do
      let(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
      before { sign_in_as(admin) }

      it 'renders the LIMITED GRID with core household fields + linked member names — no encrypted narrative' do
        get families_path
        expect(response).to have_http_status(:ok)
        body = response.body

        expect(body).to match(/class=["'][^"']*\brecord-grid__table\b/)
        expect(body).not_to match(/class=["'][^"']*\brecord-cards\b/)

        expect(body).to include('Harbor House')
        expect(body).to include('HH-1')
        expect(body).to match(/record-grid__tag--type/)
        expect(body).to include(family_path(family))

        expect(body).to include('Mem Ber')
        expect(body).to match(/record-grid__member-link/)
        expect(body).to include(client_path(member))

        expect(body).not_to include('FAMILY_SENTINEL_DO_NOT_LEAK')

        expect(body).to include('family-search-form')
        expect(body).to match(/name=["']family_grid\[order\]["']/)
      end
    end

    context 'as manager (card grid)' do
      let(:manager) { create(:user, :manager, password: password, password_confirmation: password) }
      before { sign_in_as(manager) }

      it 'renders the CARD grid, not the limited grid' do
        get families_path
        expect(response).to have_http_status(:ok)
        expect(response.body).to match(/class=["'][^"']*\brecord-cards\b/)
        expect(response.body).not_to match(/class=["'][^"']*\brecord-grid__table\b/)
      end
    end
  end
end
