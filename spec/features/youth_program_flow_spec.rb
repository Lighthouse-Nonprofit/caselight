# frozen_string_literal: true
require 'rails_helper'
require 'rake'
require Rails.root.join('spec', 'support', 'youth_flavor')

# Youth-flavor batch Y6 — the youth taxonomy end-to-end through the UI, on the
# REAL seeds (rake youth:*, not factories):
#   * multi-tracking program pane offers every ¡Por Vida! tracking (Y2's
#     per-tracking clocks made >1 tracking safe)
#   * a backdated service entry (entry_date) saves and orders the timeline
#   * restricted youth forms follow the Phase-5 sensitivity policy (admin sees,
#     strategic overviewer never does)
describe 'Youth program flow', js: true do
  include_context 'youth flavor' # S1: youth seeds refuse on another flavor
  before(:all) do
    Rake.application.rake_require('tasks/youth_taxonomy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  let!(:admin)  { create(:user, roles: 'admin') }
  let!(:client) { create(:client, given_name: 'Yram', family_name: 'Tset', state: 'accepted') }

  def seed_youth(*tasks)
    ENV['TENANT'] = Apartment::Tenant.current
    saved = $stdout
    $stdout = StringIO.new
    tasks.each do |t|
      Rake::Task[t].reenable
      Rake::Task[t].invoke
    end
  ensure
    $stdout = saved
    ENV.delete('TENANT')
  end

  before { login_as admin }

  scenario 'the ¡Por Vida! pane offers all five trackings and saves a backdated entry' do
    seed_youth('youth:seed_programs')
    pv = ProgramStream.find_by(name: '¡Por Vida!')
    create(:client_enrollment, client: client, program_stream: pv,
                               enrollment_date: Time.zone.today - 60,
                               properties: { 'School Site' => 'Santa Maria HS' })

    visit client_client_enrollments_path(client)
    click_button 'Add Tracking' # the multi-tracking dropdown toggle (a button, not a link)
    within('.dropdown-menu', match: :first) do
      ['Case Management Contact', 'Mentorship Contact', 'Academic Check-in (Aeries)',
       'Workshop / Student Engagement', 'SMART Goals Review'].each do |name|
        expect(page).to have_link(name)
      end
      click_link 'Mentorship Contact'
    end

    backdated = (Time.zone.today - 14).iso8601
    within('#new_client_enrollment_tracking') do
      page.execute_script(
        "const el = document.querySelector('input[name=\"client_enrollment_tracking[entry_date]\"]');" \
        "el.value = '#{backdated}';" \
        "el.dispatchEvent(new Event('input', {bubbles: true}));" \
        "el.dispatchEvent(new Event('change', {bubbles: true}));"
      )
      find('select', match: :first).find(:option, 'Phone Call').select_option
      click_button 'Save'
    end
    expect(page).to have_content('Tracking Program has been successfully created.')

    entry = ClientEnrollmentTracking.order(:created_at).last
    expect(entry.entry_date).to eq(Time.zone.today - 14)
    expect(entry.tracking.name).to eq('Mentorship Contact')
  end

  scenario 'restricted youth forms are admin-visible and overviewer-invisible' do
    seed_youth('youth:seed_taxonomy')
    safety = CustomField.find_by(entity_type: 'Client', form_title: 'Youth Safety Plan')
    intake = CustomField.find_by(entity_type: 'Client', form_title: 'Referral & Intake')
    [safety, intake].each do |cf|
      CustomFieldProperty.create!(custom_field_id: cf.id, custom_formable_type: 'Client',
                                  custom_formable_id: client.id,
                                  properties: { cf.fields.first['label'] => 'synthetic' })
    end

    visit client_forms_path(client)
    expect(page).to have_content('Youth Safety Plan')
    expect(page).to have_content('Referral & Intake')

    logout(:user)
    login_as create(:user, roles: 'strategic overviewer')
    visit client_forms_path(client)
    expect(page).to have_content('Referral & Intake')
    expect(page).not_to have_content('Youth Safety Plan')
  end
end
