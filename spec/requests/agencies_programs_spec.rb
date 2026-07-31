# frozen_string_literal: true
require 'rails_helper'

# Data-task batch D1 — agencies <-> programs + filtered-individuals links:
#   * the agency modal's programs multi-select round-trips through agency_params
#   * agencies#index: Programs column (links to the program page) + the agency NAME
#     links to the individuals grid pre-filtered by that agency (agencies_name filter)
#   * referral_sources#index: the source name links to the grid pre-filtered by
#     referral_source_id
#   * program_streams#show: partner agencies row
RSpec.describe 'Agencies <-> programs (D1)', type: :request do
  include Devise::Test::IntegrationHelpers
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:admin) { create(:user, :admin) }
  let!(:agency) { Agency.create!(name: 'Riverside Housing Partners', description: 'Housing referrals') }
  let!(:program_stream) { create(:program_stream, name: 'Employment Readiness') }

  before { sign_in admin }

  it 'links programs to an agency through the modal params and renders the column' do
    patch agency_path(agency), params: { agency: { name: agency.name, program_stream_ids: [program_stream.id] } }
    expect(agency.reload.program_streams).to contain_exactly(program_stream)

    get agencies_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Employment Readiness')
    # program streams live under /programs since the investor round's URL rename
    expect(response.body).to include("/programs/#{program_stream.id}")
  end

  it 'clears the links when the modal submits none and prevents duplicates at the model' do
    agency.program_streams = [program_stream]
    expect { AgencyProgramStream.create!(agency: agency, program_stream: program_stream) }
      .to raise_error(ActiveRecord::RecordInvalid)

    patch agency_path(agency), params: { agency: { name: agency.name, program_stream_ids: [''] } }
    expect(agency.reload.program_streams).to be_empty
  end

  it 'links the agency name to the individuals grid filtered by that agency' do
    get agencies_path
    # locale + params are alphabetized in rendered hrefs — assert fragments, not literals
    expect(response.body).to include('client_grid%5Bagencies_name%5D%5B%5D=Riverside+Housing+Partners')
  end

  it 'links the referral source name to the individuals grid filtered by that source' do
    source = create(:referral_source, name: 'County Welcome Center')
    get referral_sources_path
    expect(response.body).to include("client_grid%5Breferral_source_id%5D=#{source.id}")
  end

  it 'shows partner agencies on the program page' do
    agency.program_streams = [program_stream]
    get program_stream_path(program_stream)
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Partner agencies')
    expect(response.body).to include('Riverside Housing Partners')
  end

  it 'destroying an agency removes its program links but not the program' do
    agency.program_streams = [program_stream]
    expect { delete agency_path(agency) }.to change(AgencyProgramStream, :count).by(-1)
    expect(ProgramStream.exists?(program_stream.id)).to be(true)
  end
end
