# frozen_string_literal: true
require 'rails_helper'

# Reports batch — the tier gate + scoping matrix for GET /reports/:slug.
# Tier picks WHICH definitions a role may run (server-side authorize!); the data
# inside every report flows through Client.accessible_by, so two workers with
# disjoint caseloads must see disjoint numbers.
RSpec.describe 'GET /reports/:slug', type: :request do
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  def make_user(roles)
    create(:user, roles: roles, password: password, password_confirmation: password)
  end

  let(:program) { create(:program_stream, name: 'Housing') }

  context 'leadership slug (served-summary, resettlement flavor active in test)' do
    it 'renders for admin with zero-count rows' do
      program
      sign_in_as(make_user('admin'))
      get report_path('served-summary')
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('Housing')
      expect(response.body).to include(I18n.t('reports.registry.served_summary.title'))
    end

    it 'renders read-only for strategic overviewer' do
      sign_in_as(make_user('strategic overviewer'))
      get report_path('served-summary')
      expect(response).to have_http_status(:ok)
    end

    it 'redirects manager (leadership tier not granted)' do
      sign_in_as(make_user('manager'))
      get report_path('served-summary')
      expect(response).to have_http_status(:redirect)
    end

    it 'manager CAN run a manager-tier report (worker-caseloads)' do
      sign_in_as(make_user('manager'))
      get report_path('worker-caseloads')
      expect(response).to have_http_status(:ok)
      expect(response.body).to include(I18n.t('reports.registry.worker_caseloads.title'))
    end

    it 'case worker CAN run a worker-tier report (my-caseload-progress)' do
      sign_in_as(make_user('case worker'))
      get report_path('my-caseload-progress')
      expect(response).to have_http_status(:ok)
    end

    it 'redirects case worker' do
      sign_in_as(make_user('case worker'))
      get report_path('served-summary')
      expect(response).to have_http_status(:redirect)
    end
  end

  context 'slug resolution' do
    before { sign_in_as(make_user('admin')) }

    it '404s an unknown slug' do
      get report_path('does-not-exist')
      expect(response).to have_http_status(:not_found)
    end

    it '404s a wrong-flavor slug (youth report on a resettlement box)' do
      get report_path('youth-served')
      expect(response).to have_http_status(:not_found)
    end
  end

  context 'ability scoping inside a report' do
    it 'admin sees org-wide counts; a caseload-scoped viewer would see fewer' do
      worker = make_user('case worker')
      mine = create(:client, state: 'accepted', users: [worker])
      other = create(:client, state: 'accepted')
      create(:client_enrollment, client: mine, program_stream: program,
                                 enrollment_date: Time.zone.today)
      create(:client_enrollment, client: other, program_stream: program,
                                 enrollment_date: Time.zone.today)

      sign_in_as(make_user('admin'))
      get report_path('served-summary', params: { from: (Time.zone.today - 30).iso8601,
                                                  to: Time.zone.today.iso8601 })
      expect(response).to have_http_status(:ok)
      housing_row = response.body[/Housing.*?<\/tr>/m]
      expect(housing_row).to include('<td>2</td>') # both clients in the admin scope

      # The worker can't run this leadership report at all — but the SCOPE math is
      # proven by building the report over the worker's ability directly:
      scoped = Reports::Registry.find!('served-summary')
                                .build(clients: Client.accessible_by(Ability.new(worker)),
                                       period: Reports::Period.new(preset: :custom,
                                                                   range: (Time.zone.today - 30)..Time.zone.today))
      housing = scoped.sections.sole.rows.find { |r| r.first == 'Housing' }
      expect(housing[1]).to eq(1) # only the worker's own client
    end
  end

  context 'period handling' do
    before { sign_in_as(make_user('admin')) }

    it 'accepts a custom range and shows its label' do
      get report_path('served-summary', params: { from: '2026-01-01', to: '2026-06-30' })
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('2026-01-01')
      expect(response.body).to include('2026-06-30')
    end
  end

  # R2 — export formats. Tier denial applies to every format; CSV parses back
  # (never substring-matched); PDF = real bytes + the sandbox CSP posture.
  context 'exports' do
    it 'CSV round-trips with section title, headers, and zero-count rows' do
      program
      sign_in_as(make_user('admin'))
      get report_path('served-summary', format: :csv)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('text/csv')
      table = CSV.parse(response.body)
      expect(table.first.first).to eq(I18n.t('reports.registry.served_summary.title'))
      header_row = table.find { |r| r.first == I18n.t('reports.registry.served_summary.columns.program') }
      expect(header_row).to include(I18n.t('reports.registry.served_summary.columns.individuals'))
      housing = table.find { |r| r.first == 'Housing' }
      expect(housing[1..3]).to eq(%w[0 0 0]) # zero counts REPORTED, not omitted
    end

    it 'PDF returns real bytes inline under a sandboxing CSP' do
      skip 'chromium not available in this environment' unless PdfRenderer.available?
      sign_in_as(make_user('admin'))
      get report_path('served-summary', format: :pdf)
      expect(response).to have_http_status(:ok)
      expect(response.media_type).to eq('application/pdf')
      expect(response.body[0, 5]).to eq('%PDF-')
      expect(response.headers['Content-Security-Policy']).to eq('sandbox')
      expect(response.headers['Content-Disposition']).to include('inline')
    end

    it 'tier denial covers exports too (worker CSV on a leadership slug redirects)' do
      sign_in_as(make_user('case worker'))
      get report_path('served-summary', format: :csv)
      expect(response).to have_http_status(:redirect)
    end
  end
end
