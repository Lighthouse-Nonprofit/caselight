# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# Phase 6 (U8) — AC-2(3) inactive-account auto-disable. Contract: nil threshold => report-only
# (nobody disabled, ever); set threshold => only stale accounts disabled, values-free AccessLog row
# per disable, dry-run without CONFIRM=1, and the last enabled admin is NEVER auto-disabled.
RSpec.describe 'accounts:disable_inactive', type: :model do
  before(:all) do
    Rake.application.rake_require('tasks/accounts', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  before(:each) do
    AccessLog.unscoped.delete_all rescue nil
    EnforcementSetting.delete_all
    EnforcementSetting.clear_cache!
    allow(Organization).to receive(:pluck).with(:short_name).and_return([Apartment::Tenant.current])
  end

  after(:each) do
    AccessLog.unscoped.delete_all rescue nil
    EnforcementSetting.delete_all
    EnforcementSetting.clear_cache!
    ENV.delete('CONFIRM')
  end

  def run_task
    EnforcementSetting.clear_cache! # the rake reads via the RequestStore memo; no request cycle in specs
    Rake::Task['accounts:disable_inactive'].reenable
    Rake::Task['accounts:disable_inactive'].invoke
  end

  def make_stale(user, days: 120)
    user.update_columns(current_sign_in_at: days.days.ago, last_sign_in_at: days.days.ago,
                        created_at: days.days.ago)
  end

  let!(:admin) { create(:user, roles: 'admin') }

  it 'validates the 30-day floor on the setting' do
    expect(EnforcementSetting.new(inactive_disable_days: 10)).not_to be_valid
    expect(EnforcementSetting.new(inactive_disable_days: 30)).to be_valid
  end

  it 'disables nobody when the threshold is unset (report-only), even with CONFIRM' do
    worker = create(:user, roles: 'case worker')
    make_stale(worker)
    ENV['CONFIRM'] = '1'
    expect { run_task }.to output(/report-only/).to_stdout
    expect(worker.reload.disable?).to be false
  end

  it 'dry-runs without CONFIRM even when the threshold is set' do
    EnforcementSetting.create!(inactive_disable_days: 60)
    worker = create(:user, roles: 'case worker')
    make_stale(worker)
    expect { run_task }.to output(/DRY-RUN would disable/).to_stdout
    expect(worker.reload.disable?).to be false
    expect(AccessLog.unscoped.where(event_type: 'account_disabled').count).to eq(0)
  end

  it 'disables only stale accounts with CONFIRM=1 and audits each, without touching roles' do
    EnforcementSetting.create!(inactive_disable_days: 60)
    stale = create(:user, roles: 'case worker')
    make_stale(stale)
    fresh = create(:user, roles: 'case worker')
    fresh.update_columns(current_sign_in_at: 1.day.ago)

    ENV['CONFIRM'] = '1'
    run_task

    expect(stale.reload.disable?).to be true
    expect(stale.roles).to eq('case worker')
    expect(fresh.reload.disable?).to be false
    expect(admin.reload.disable?).to be false # admin is fresh (just created… but created_at now)

    log = AccessLog.unscoped.where(event_type: 'account_disabled').last
    expect(log).to be_present
    expect(log.user_id).to eq(stale.id)
    expect(log.metadata['reason']).to eq('inactivity')
    expect(log.metadata['threshold_days']).to eq(60)
  end

  it 'never disables the last enabled admin' do
    EnforcementSetting.create!(inactive_disable_days: 60)
    make_stale(admin)
    ENV['CONFIRM'] = '1'
    expect { run_task }.to output(/last enabled admin/).to_stdout
    expect(admin.reload.disable?).to be false
  end

  it 'disables a stale admin when another enabled admin remains' do
    EnforcementSetting.create!(inactive_disable_days: 60)
    make_stale(admin)
    create(:user, roles: 'admin') # a second, fresh admin
    ENV['CONFIRM'] = '1'
    run_task
    expect(admin.reload.disable?).to be true
  end
end

RSpec.describe 'Access review: disabled staff with caseloads', type: :request do
  after(:each) { ClientHistory.unscoped.delete_all rescue nil }

  let(:password) { 'SecurePass123!' }

  it 'lists disabled users still holding caseload assignments' do
    admin  = create(:user, roles: 'admin')
    ghost  = create(:user, roles: 'case worker', first_name: 'Ghost', last_name: 'Holder')
    client = create(:client)
    client.users << ghost
    ghost.update_columns(disable: true)

    post user_session_path, params: { user: { email: admin.email, password: password } }
    get access_review_path
    expect(response).to have_http_status(:ok)
    expect(response.body).to include('Disabled Staff Still Holding Caseloads')
    expect(response.body).to include('Ghost Holder')
  end
end
