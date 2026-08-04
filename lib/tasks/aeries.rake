# frozen_string_literal: true

# SCH3 — Aeries sync entry point. SCAFFOLD posture: refuses until the env creds
# exist (which only happens after the SMJUHSD data-sharing authorization), and
# DRY-RUN unless CONFIRM=1. Output is values-free (counts only).
namespace :aeries do
  desc 'Sync Aeries academic records into Academic Check-in entries. DRY_RUN unless CONFIRM=1.'
  task sync: :environment do
    # S1: Aeries academic data only exists in the youth taxonomy.
    unless Rails.application.config.x.flavor == 'youth'
      abort "[aeries] refusing: FLAVOR=#{Rails.application.config.x.flavor.inspect} — youth boxes only."
    end
    abort '[aeries] not configured (AERIES_BASE_URL/AERIES_API_KEY) — the DSA gate.' unless Aeries::Client.enabled?
    tenant = ENV['TENANT'] or abort '[aeries] TENANT= required'
    endpoint = ENV['AERIES_ENDPOINT'].presence || 'api/v5/schools'

    Apartment::Tenant.switch(tenant) do
      records = Aeries::Client.new.get(endpoint)
      result = Aeries::AcademicSync.new(records, confirm: ENV['CONFIRM'] == '1').run!
      puts "[aeries] #{result.dry_run ? 'DRY RUN' : 'APPLIED'}: matched=#{result.matched} " \
           "unmatched=#{result.unmatched} created=#{result.created} skipped_existing=#{result.skipped_existing}"
    end
  end
end
