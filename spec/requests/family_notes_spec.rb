# frozen_string_literal: true
require 'rails_helper'

# UX round 3 (B2) — household notes CRUD + gating on the family hub's Notes tab. Contracts:
#   * a manager (can :manage, Family/FamilyNote) has full CRUD; author is stamped
#   * strategic_overviewer mirrors the CaseNote treatment: NO access to household narrative
#     (the cannot :manage revokes read too) and no Notes tab in the header
#   * index reads are audited (AccessAudit)
RSpec.describe 'Family notes', type: :request do
  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  let(:manager)    { create(:user, roles: 'manager', password: password, password_confirmation: password) }
  let(:overviewer) { create(:user, :strategic_overviewer, password: password, password_confirmation: password) }

  let!(:family) { create(:family, name: 'Notes Household') }
  let!(:note)   { create(:family_note, family: family, note: 'NOTES_SPEC_BODY utilities transferred') }

  describe 'manager' do
    before { sign_in_as(manager) }

    it 'lists notes on the Notes tab with the header chip' do
      get family_family_notes_path(family)
      expect(response).to have_http_status(:ok)
      body = response.body

      expect(body).to include('client-hub__name')
      expect(body).to include('Notes Household')
      expect(body).to include('NOTES_SPEC_BODY')
      expect(CGI.unescapeHTML(body)).to include(new_family_family_note_path(family))
    end

    it 'creates a note stamped with the author' do
      expect do
        post family_family_notes_path(family), params: {
          family_note: { meeting_date: Date.today.to_s, attendee: 'Home visit', note: 'New body' }
        }
      end.to change { family.family_notes.count }.by(1)
      expect(response).to redirect_to(family_family_notes_path(family, locale: 'en'))
      expect(family.family_notes.most_recents.first.user).to eq(manager)
    end

    it 'rejects a blank note body' do
      post family_family_notes_path(family), params: {
        family_note: { meeting_date: Date.today.to_s, note: '' }
      }
      expect(response).to have_http_status(:ok) # re-rendered form
      expect(family.family_notes.count).to eq(1)
    end

    it 'updates and destroys' do
      patch family_family_note_path(family, note), params: { family_note: { note: 'Edited body' } }
      expect(note.reload.note).to eq('Edited body')

      delete family_family_note_path(family, note)
      expect(family.family_notes.count).to eq(0)
    end

    it 'audits the index read' do
      AccessLog.delete_all
      get family_family_notes_path(family)
      expect(response).to have_http_status(:ok)
      expect(AccessLog.count).to be >= 1
    end

    # Investor UX round (2026-07): trash left the note cards; Delete lives on the edit page,
    # anchored at the opposite outer edge (docs/ui-conventions.md destructive placement).
    it 'note cards carry a labeled Edit but no delete; the edit page carries the delete' do
      get family_family_notes_path(family)
      body = response.body
      expect(body).to include('>Edit<')
      # scoped to the note record — the sidebar Log-out is data-method="delete" on every page
      expect(body).not_to match(%r{data-method="delete" href="[^"]*family_notes/#{note.id}})
      expect(body).not_to include('fa-trash')

      get edit_family_family_note_path(family, note)
      expect(response).to have_http_status(:ok)
      expect(response.body).to match(%r{data-method="delete" href="[^"]*family_notes/#{note.id}})
      expect(response.body).to include('>Delete<')
    end
  end

  describe 'strategic overviewer (no household-narrative need-to-know)' do
    before { sign_in_as(overviewer) }

    it 'is denied the Notes index and never sees the note body' do
      get family_family_notes_path(family)
      expect(response).not_to have_http_status(:ok) # CanCan redirect
      expect(response.body).not_to include('NOTES_SPEC_BODY')
    end

    it 'sees no Notes tab on the family header' do
      get family_path(family)
      expect(response).to have_http_status(:ok)
      expect(CGI.unescapeHTML(response.body)).not_to include(family_family_notes_path(family))
    end

    it 'cannot create a note' do
      expect do
        post family_family_notes_path(family), params: {
          family_note: { meeting_date: Date.today.to_s, note: 'Sneaky' }
        }
      end.not_to change { family.family_notes.count }
    end
  end
end
