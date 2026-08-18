# frozen_string_literal: true

namespace :notes do
  desc 'Seed default Progress Note types + contact Locations (idempotent, per tenant). ' \
       'The flexible note (voicemails, follow-up texts, ...) needs these reference rows to be useful.'
  task seed_types: :environment do
    tenant = ENV['TENANT'] || 'cases'
    types = ['In-person', 'Phone call', 'Voicemail', 'Text / SMS', 'Email', 'Follow-up text',
             'Home visit', 'Video call', 'Collateral contact', 'Other',
             # OCA Casebook contact types (from the real note Subjects — see SubjectClassifier::CONTACT_TYPES).
             'Parent contact', 'Drop-in', 'Attempted contact', 'Transportation', 'Check-in',
             'Intake / assessment', 'Referral', 'Closing / status', 'Individual meeting',
             'Resource / navigation']
    locations = ['Office', 'School', 'Home', 'Community', 'Phone', 'Virtual', 'Other']
    Apartment::Tenant.switch(tenant) do
      types.each { |name| ProgressNoteType.find_or_create_by!(note_type: name) }
      locations.each { |name| Location.find_or_create_by!(name: name) }
      puts "notes:seed_types [tenant=#{tenant}]: #{ProgressNoteType.count} types, #{Location.count} locations."
    end
  end
end
