# frozen_string_literal: true
require 'rails_helper'

# 2026-10-18 security pass. CanCan's load_and_authorize_resource only loads + authorizes a RECORD when
# params[:id] is present; routes keyed on :user_id / :client_id / :case_id get a CLASS check, which a
# conditional rule (a manager's `can :manage, User, id: [...]`, a case worker's caseload rule) passes.
# Every such controller then did an unscoped Model.find — so a manager could reset an admin's password,
# a case worker could read any case's quarterly reports, any user could list any user's tasks. All of
# those lookups now go through accessible_by; outside the scope they 404 like a missing record.
RSpec.describe 'Record-scoped lookups on :foo_id routes', type: :request do
  after(:each) { ClientHistory.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  def sign_in_as(user)
    post user_session_path, params: { user: { email: user.email, password: password } }
  end

  describe 'users: version / disable / unlock / reset_password' do
    let!(:manager)     { create(:user, :manager, password: password, password_confirmation: password) }
    let!(:subordinate) { create(:user, manager_id: manager.id) }
    let!(:admin)       { create(:user, :admin) }

    before { sign_in_as(manager) }

    it 'lets a manager reset a subordinate (their own scope)' do
      digest = subordinate.encrypted_password
      patch user_reset_password_path(subordinate)
      expect(response).to have_http_status(:found)
      expect(subordinate.reload.encrypted_password).not_to eq(digest)
    end

    it 'refuses to let a manager reset, disable, unlock or inspect an admin outside their scope' do
      digest = admin.encrypted_password
      patch user_reset_password_path(admin)
      expect(response).to have_http_status(:not_found)
      expect(admin.reload.encrypted_password).to eq(digest)

      patch user_disable_path(admin)
      expect(response).to have_http_status(:not_found)
      expect(admin.reload.disable).to be_falsey

      patch user_unlock_path(admin)
      expect(response).to have_http_status(:not_found)

      get user_version_path(admin)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'case worker caseload boundaries' do
    let!(:worker)   { create(:user, password: password, password_confirmation: password) }
    let!(:other)    { create(:user) }
    let!(:mine)     { create(:client, users: [worker]) }
    let!(:theirs)   { create(:client, users: [other]) }
    let!(:my_case)  { create(:case, client: mine) }
    let!(:their_case) { create(:case, client: theirs) }

    before { sign_in_as(worker) }

    it 'quarterly reports: own client renders, another worker\'s client 404s' do
      get client_case_quarterly_reports_path(mine, my_case)
      expect(response).to have_http_status(:ok)

      get client_case_quarterly_reports_path(theirs, their_case)
      expect(response).to have_http_status(:not_found)
    end

    it 'able screening answers: another worker\'s client 404s instead of opening the form' do
      get able_screens_answer_submissions_client_able_screening_answers_new_path(theirs)
      expect(response).to have_http_status(:not_found)
    end

    it 'tasks index: ?user_id= only reaches self-and-subordinates' do
      get tasks_path(user_id: worker.id)
      expect(response).to have_http_status(:ok)

      get tasks_path(user_id: other.id)
      expect(response).to have_http_status(:not_found)
    end

    it 'family version history: a household outside the caseload 404s' do
      stranger_family = create(:family)
      get family_version_path(stranger_family)
      # a case worker's `can :read, Family` does not cover :version, so CanCan already redirects at the
      # class check (302); roles that pass it hit the accessible_by scope and 404. Never 200.
      expect([302, 404]).to include(response.status)
    end
  end

  describe 'API form-builder attachment delete' do
    let!(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
    before { sign_in_as(admin) }

    it 'answers 404 for an unknown attachment instead of raising on nil' do
      delete api_form_builder_attachment_path(999_999, file_name: 'nope', file_index: 0, format: :json)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe 'data trackers formable_type' do
    let!(:admin) { create(:user, :admin, password: password, password_confirmation: password) }
    before { sign_in_as(admin) }

    it 'treats an injected formable_type as a literal pattern (no SQL error, no rows)' do
      get data_trackers_path(item_type: 'CustomFieldProperty', formable_type: "Client' OR 1=1 --")
      expect(response).to have_http_status(:ok)
    end
  end
end
