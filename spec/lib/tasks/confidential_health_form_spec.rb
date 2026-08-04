# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# CMIA / AB 352 (gap G2) — the segregated confidential-health section:
#   * seeded at emergency_only, so no role sees it without an audited break-glass
#     grant (and a strategic overviewer never can, by SensitivityPolicy)
#   * its values are withheld from report output (HTML and CSV) for a viewer
#     without clearance — absence, never fabricated blanks
RSpec.describe 'confidential health form (AB 352)' do
  FORM = 'Confidential Health Information'

  before(:all) do
    Rake.application.rake_require('tasks/slo4home_taxonomy', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment) unless Rake::Task.task_defined?(:environment)
  end

  def seed!
    ENV['TENANT'] = Apartment::Tenant.current
    Rake::Task['slo4home:seed_taxonomy'].reenable
    saved = $stdout
    $stdout = StringIO.new
    Rake::Task['slo4home:seed_taxonomy'].invoke
  ensure
    $stdout = saved
    ENV.delete('TENANT')
  end

  it 'is seeded at emergency_only with the AB 352 categories' do
    seed!
    cf = CustomField.find_by(entity_type: 'Client', form_title: FORM)
    expect(cf).to be_present
    expect(cf.sensitivity).to eq('emergency_only')
    categories = cf.fields.find { |f| f['label'] == 'Category' }['values'].map { |v| v['value'] }
    expect(categories).to include('Gender-affirming care', 'Reproductive health', 'Contraception')
  end

  it 'keeps its inline sensitivity across a re-seed (classify must not downgrade it)' do
    seed!
    seed!
    expect(CustomField.find_by(form_title: FORM).sensitivity).to eq('emergency_only')
  end

  it 'is invisible to every non-admin role without a break-glass grant' do
    seed!
    cf = CustomField.find_by(form_title: FORM)
    %w[case\ worker manager strategic\ overviewer].each do |role|
      policy = SensitivityPolicy.new(create(:user, roles: role))
      expect(policy.visible_custom_field_ids).not_to include(cf.id),
        "#{role} should not see the confidential-health form without break-glass"
    end
    expect(SensitivityPolicy.new(create(:user, :admin)).visible_custom_field_ids).to include(cf.id)
  end

  it 'withholds its values from report output for an uncleared viewer' do
    seed!
    cf = CustomField.find_by(form_title: FORM)
    client = create(:client, state: 'accepted')
    CustomFieldProperty.create!(custom_field_id: cf.id, custom_formable_type: 'Client',
                               custom_formable_id: client.id,
                               properties: { 'Category' => 'Gender-affirming care',
                                             'Confidential Notes' => 'SENTINELVALUE' })
    definition = Reports::Registry.find!('demographics', flavor: 'resettlement')
    report = definition.build(clients: Client.where(id: client.id),
                              period: Reports::Period.current(:calendar_year),
                              visible_custom_field_ids: Set.new) # uncleared
    expect(report.to_csv).not_to include('SENTINELVALUE')
    expect(report.to_csv).not_to include('Gender-affirming care')
  end
end
