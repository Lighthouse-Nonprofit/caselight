# frozen_string_literal: true

namespace :notes do
  desc 'Seed default Progress Note types + contact Locations (idempotent, per tenant). ' \
       'The flexible note (voicemails, follow-up texts, ...) needs these reference rows to be useful.'
  task seed_types: :environment do
    tenant = ENV['TENANT'] || 'cases'
    # Bifurcated note families (OCA 2026-08). CONTACT = a contact-log entry (many types); CURRICULUM =
    # a session/activity narrative; GENERAL = a plain client note. See ProgressNoteType::CATEGORIES.
    contact_types = ['In-person', 'Phone call', 'Voicemail', 'Text / SMS', 'Email', 'Follow-up text',
                     'Home visit', 'Video call', 'Collateral contact', 'Other',
                     # OCA Casebook contact types (from the real note Subjects — see SubjectClassifier::CONTACT_TYPES).
                     'Parent contact', 'Drop-in', 'Attempted contact', 'Transportation', 'Check-in',
                     'Intake / assessment', 'Referral', 'Closing / status', 'Individual meeting',
                     'Resource / navigation']
    locations = ['Office', 'School', 'Home', 'Community', 'Phone', 'Virtual', 'Other']
    Apartment::Tenant.switch(tenant) do
      # find_or_create then set the category, so existing rows (seeded before the category column) are
      # corrected in place — idempotent.
      contact_types.each { |name| ProgressNoteType.find_or_create_by!(note_type: name).update!(category: 'contact') }
      ProgressNoteType.find_or_create_by!(note_type: ProgressNoteType::CURRICULUM_TYPE).update!(category: 'curriculum')
      ProgressNoteType.find_or_create_by!(note_type: ProgressNoteType::GENERAL_TYPE).update!(category: 'general')
      # The legacy import bucket, if present, is a general catch-all until notes:recategorize moves its
      # notes onto the Curriculum/General types above.
      ProgressNoteType.where(note_type: 'Imported from Casebook').update_all(category: 'general')
      locations.each { |name| Location.find_or_create_by!(name: name) }
      puts "notes:seed_types [tenant=#{tenant}]: #{ProgressNoteType.count} types " \
           "(contact=#{ProgressNoteType.contact.count} curriculum=#{ProgressNoteType.curriculum.count} " \
           "general=#{ProgressNoteType.general.count}), #{Location.count} locations."
    end
  end

  desc 'Re-type imported ProgressNotes into the Contact / Curriculum / General families by re-reading ' \
       'each note\'s original Subject (stored in additional_note). Idempotent; only touches notes still ' \
       'on the import-managed buckets (Imported from Casebook / Curriculum / General), never hand-set types.'
  task recategorize: :environment do
    tenant = ENV['TENANT'] || 'cases'
    Apartment::Tenant.switch(tenant) do
      curriculum = ProgressNoteType.find_or_create_by!(note_type: ProgressNoteType::CURRICULUM_TYPE) { |t| t.category = 'curriculum' }
      curriculum.update!(category: 'curriculum')
      general    = ProgressNoteType.find_or_create_by!(note_type: ProgressNoteType::GENERAL_TYPE) { |t| t.category = 'general' }
      general.update!(category: 'general')
      contact_by_name = {}  # memoized contact-type lookup

      # Only re-evaluate notes sitting on the import buckets — leave any hand-set contact type alone.
      managed_ids = ProgressNoteType.where(note_type: ['Imported from Casebook', ProgressNoteType::CURRICULUM_TYPE, ProgressNoteType::GENERAL_TYPE]).ids
      scope = ProgressNote.where(progress_note_type_id: managed_ids)
      moved = Hash.new(0)
      scope.find_each do |note|
        result = Casebook::SubjectClassifier.classify(note.additional_note.to_s)
        target =
          case result && result[:kind]
          when :session, :bare_session
            curriculum
          when :contact
            name = result[:note_type]
            contact_by_name[name] ||= ProgressNoteType.find_or_create_by!(note_type: name) { |t| t.category = 'contact' }
          else
            # :tracking / :assessment_marker / nil — a general client note (curriculum ACTIVITY is
            # captured separately as a ClientEnrollmentTracking under Programs).
            general
          end
        next if note.progress_note_type_id == target.id
        note.update_columns(progress_note_type_id: target.id)
        moved[target.note_type] += 1
      end
      puts "notes:recategorize [tenant=#{tenant}]: re-typed #{moved.values.sum} note(s) -> " \
           "#{moved.map { |k, v| "#{k}=#{v}" }.join(', ').presence || 'none (already categorized)'}"
    end
  end
end
