# frozen_string_literal: true
require 'rails_helper'

# Regression proof for the Phase-5.6 notifications fix: `authorize! :read, Notification`
# referenced a nonexistent constant, so GET /notifications raised NameError (500) for
# EVERY role — the notification-bell page was fully broken. The fix authorizes the
# SYMBOL :notification (class-less pattern, like :break_glass_grant) and adds the
# common `can :read, :notification` grant the original comment claimed existed.
RSpec.describe 'Notifications page (Phase-5.6 authorize fix)', type: :request do
  include Devise::Test::IntegrationHelpers

  # The page is only ever entered through the bell-dropdown links, which always carry a
  # param (layouts/_notification.haml) — so those are the flows the NameError broke and
  # the flows this spec pins. (A bare param-less GET has never had a template; that
  # pre-existing 406 is out of scope here.)
  shared_examples 'renders the notification views' do |role|
    before { sign_in create(:user, roles: role) }

    it "renders the custom-field notification view for a #{role}" do
      get notifications_path(entity_custom_field: 'client_due_today')
      expect(response).to have_http_status(:ok)
    end

    it "renders the enrollment-tracking notification view for a #{role}" do
      get notifications_path(client_enrollment_tracking: 'client_enrollment_tracking_overdue')
      expect(response).to have_http_status(:ok)
    end
  end

  # admin passes via `can :manage, :all`; a non-admin role proves the common grant.
  include_examples 'renders the notification views', 'admin'
  include_examples 'renders the notification views', 'case worker'
end
