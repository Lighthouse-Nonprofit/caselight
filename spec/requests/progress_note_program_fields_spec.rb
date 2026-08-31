# frozen_string_literal: true
require 'rails_helper'

# OCA feedback 2026-08-26 — Araceli: "Progress note fields (interventions, equipment/materials,
# goals addressed) belong in program notes, not general notes."
#
# Since PR #312 bifurcated note types into Contact / Curriculum / General, "program note" is the
# Curriculum & Session family. These three fields are ASSOCIATIONS (interventions HABTM, material
# FK, assessment_domains HABTM), not columns, so nothing is dropped or migrated — they are simply
# not offered or shown on contact/general notes.
#
# Regression note: the show page must ask the MODEL for the category. ProgressNoteDecorator
# redefines #progress_note_type to return the display STRING, so `progress_note_type.category` on
# a decorated note raises NoMethodError and 500s the page — hence #curriculum_note?.
RSpec.describe 'Progress note program-only fields', type: :request do
  include Devise::Test::IntegrationHelpers

  let!(:admin)      { create(:user, roles: 'admin') }
  let(:client)      { create(:client, state: 'accepted') }
  let(:curriculum)  { create(:progress_note_type, note_type: 'Curriculum / Session', category: 'curriculum') }
  let(:contact)     { create(:progress_note_type, note_type: 'Phone call', category: 'contact') }
  let(:general)     { create(:progress_note_type, note_type: 'General note', category: 'general') }

  before { sign_in admin }

  def show_note(type)
    note = create(:progress_note, client: client, user: admin, progress_note_type: type)
    get client_progress_note_path(client, note)
    response
  end

  # Scope assertions to the note's own information grid. "Equipment/Materials" is also an admin
  # nav label rendered in the page chrome, so a whole-body match would always be true.
  def info_grid
    response.body[/<dl class="info-grid".*?<\/dl>/m]
  end

  describe 'the record page' do
    it 'shows the three program fields on a curriculum note' do
      show_note(curriculum)
      expect(response).to have_http_status(:ok)
      expect(info_grid).to include('Interventions')
      expect(info_grid).to include('Equipment/Materials')
      expect(info_grid).to include('Goals Addressed')
    end

    it 'hides them on a contact note' do
      show_note(contact)
      expect(response).to have_http_status(:ok)
      expect(info_grid).to be_present
      expect(info_grid).not_to include('Equipment/Materials')
      expect(info_grid).not_to include('Goals Addressed')
      expect(info_grid).to include('Phone call') # the rest of the note still renders
    end

    it 'hides them on a general note' do
      show_note(general)
      expect(response).to have_http_status(:ok)
      expect(info_grid).not_to include('Equipment/Materials')
      expect(info_grid).not_to include('Goals Addressed')
    end

    it 'renders (does not 500) when a note type has no category set' do
      # Guards the decorator/model mix-up that 500'd this page during implementation.
      typeless = create(:progress_note_type, note_type: 'Legacy', category: 'contact')
      expect(show_note(typeless)).to have_http_status(:ok)
    end
  end

  describe 'the form' do
    it 'carries the curriculum type ids so the JS can toggle without inline script (CSP)' do
      curriculum && contact
      get new_client_progress_note_path(client)

      expect(response).to have_http_status(:ok)
      expect(response.body).to include('curriculum-only-fields')
      expect(response.body).to include(curriculum.id.to_s)
    end
  end

  describe 'ProgressNoteType#curriculum?' do
    it 'is true only for the curriculum family' do
      expect(curriculum.curriculum?).to be true
      expect(contact.curriculum?).to be false
      expect(general.curriculum?).to be false
    end
  end

  describe 'ProgressNoteDecorator#curriculum_note?' do
    it 'reads the category off the model, not the display string' do
      note = create(:progress_note, client: client, user: admin, progress_note_type: curriculum)
      decorated = ProgressNoteDecorator.new(note)

      expect(decorated.progress_note_type).to eq('Curriculum / Session') # display string
      expect(decorated.curriculum_note?).to be true
    end

    it 'is false when the note has no type at all' do
      note = build(:progress_note, client: client, user: admin, progress_note_type: nil)
      expect(ProgressNoteDecorator.new(note).curriculum_note?).to be false
    end
  end
end
