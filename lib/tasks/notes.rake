# frozen_string_literal: true

namespace :notes do
  desc 'Seed default Progress Note types + contact Locations (idempotent, per tenant). ' \
       'The flexible note (voicemails, follow-up texts, ...) needs these reference rows to be useful.'
  task seed_types: :environment do
    tenant = ENV['TENANT'] || 'cases'
    types = ['In-person', 'Phone call', 'Voicemail', 'Text / SMS', 'Email', 'Follow-up text',
             'Home visit', 'Video call', 'Collateral contact', 'Other']
    locations = ['Office', 'School', 'Home', 'Community', 'Phone', 'Virtual', 'Other']
    Apartment::Tenant.switch(tenant) do
      types.each { |name| ProgressNoteType.find_or_create_by!(note_type: name) }
      locations.each { |name| Location.find_or_create_by!(name: name) }
      puts "notes:seed_types [tenant=#{tenant}]: #{ProgressNoteType.count} types, #{Location.count} locations."
    end
  end
end
