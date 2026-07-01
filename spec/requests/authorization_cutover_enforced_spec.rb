# frozen_string_literal: true
require 'rails_helper'

# Phase 5.6 (AC-3) ENFORCE-ON targeted proofs for the four formerly-default-open holes + the two resolved
# shell actions. Guards against WRONG-SUBJECT authorize! regressions the route-smoke is blind to (it only
# checks the authorization_not_performed fingerprint, treating a wrong DENY as an acceptable redirect).
# Forces enforce_authorization ON for the example, restores after.
RSpec.describe 'Phase 5.6 enforced authorization (lowest-priv legit role not denied)', type: :request do
  include Devise::Test::IntegrationHelpers

  around(:each) do |ex|
    prev = Rails.application.config.x.enforce_authorization
    Rails.application.config.x.enforce_authorization = true
    begin; ex.run; ensure; Rails.application.config.x.enforce_authorization = prev; end
  end

  def static_403?
    response.status == 403 && response.body == 'Not authorized'
  end

  it 'api/form_builder_attachments#destroy: a case_worker deleting a file off a client custom-field form is NOT static-403' do
    worker = create(:user, roles: 'case worker')
    sign_in worker
    client = create(:client)
    cfp = create(:custom_field_property, custom_formable: client) # form_buildable parent the worker :manages
    attachment = create(:form_builder_attachment, name: 'attachment',
                        form_buildable_type: 'CustomFieldProperty', form_buildable_id: cfp.id)
    delete "/api/form_builder_attachments/#{attachment.id}", params: { file_name: 'attachment', file_index: 0 }
    expect(static_403?).to be(false) # parent-record authz (:update on the CFP) passes for case_worker
  end

  it 'client_advanced_searches#index: every role reaches it without the static 403 (all hold :read Client)' do
    User::ROLES.each do |role|
      u = create(:user, roles: role)
      sign_in u
      get '/client_advanced_searches'
      expect(static_403?).to be(false), "role #{role} got static 403 on client_advanced_searches#index"
      sign_out u
    end
  end

  it 'papertrail_queries#index and notifications#index authorize (no AuthorizationNotPerformed) for admin' do
    AccessLog.delete_all
    admin = create(:user, roles: 'admin')
    sign_in admin
    get '/papertrail_queries'
    expect(static_403?).to be(false)
    get '/notifications'
    expect(static_403?).to be(false)
    expect(AccessLog.where(event_type: 'authorization_not_performed').count).to eq(0)
  ensure
    AccessLog.delete_all
  end
end
