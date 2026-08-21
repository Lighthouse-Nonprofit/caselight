# frozen_string_literal: true
require 'rails_helper'
require 'rake'

# notes:recategorize re-types the imported ProgressNotes into the Contact / Curriculum / General
# families by re-reading each note's original Subject (preserved in additional_note). It only touches
# notes still on the import-managed buckets, and is idempotent.
RSpec.describe 'notes:recategorize rake', type: :task do
  before(:all) do
    Rake.application.rake_require('tasks/notes', [Rails.root.join('lib').to_s])
    Rake::Task.define_task(:environment)
  end

  let(:import_type) { ProgressNoteType.create!(note_type: 'Imported from Casebook', category: 'general') }
  let(:client)      { create(:client) }

  def note_with(subject)
    create(:progress_note, client: client, progress_note_type: import_type, additional_note: subject)
  end

  def run!
    ENV['TENANT'] = Apartment::Tenant.current
    Rake::Task['notes:recategorize'].reenable
    Rake::Task['notes:recategorize'].invoke
  ensure
    ENV.delete('TENANT')
  end

  it 'sorts imported notes into Curriculum / Contact / General by their original subject' do
    session = note_with('Week 2 Joven Noble: Palabra') # -> :session  => Curriculum / Session
    contact = note_with('Phone call to mom')           # -> :contact  => Phone call (contact family)
    general = note_with('Miscellaneous update')        # -> nil       => General note

    run!

    expect(session.reload.progress_note_type.note_type).to eq('Curriculum / Session')
    expect(session.progress_note_type.category).to eq('curriculum')

    expect(contact.reload.progress_note_type.note_type).to eq('Phone call')
    expect(contact.progress_note_type.category).to eq('contact')

    expect(general.reload.progress_note_type.note_type).to eq('General note')
    expect(general.progress_note_type.category).to eq('general')
  end

  it 'is idempotent — a second run moves nothing' do
    note_with('Week 2 Joven Noble: Palabra')
    note_with('Miscellaneous update')
    run!
    types_after_first = ProgressNote.pluck(:progress_note_type_id).sort
    run!
    expect(ProgressNote.pluck(:progress_note_type_id).sort).to eq(types_after_first)
  end

  it 'never re-types a note that already carries a hand-set contact type' do
    phone = ProgressNoteType.create!(note_type: 'Phone call', category: 'contact')
    # a note deliberately typed Phone call, but whose subject looks like a curriculum session
    manual = create(:progress_note, client: client, progress_note_type: phone, additional_note: 'Week 5 Girasol')
    run!
    expect(manual.reload.progress_note_type).to eq(phone) # left alone (not on an import-managed bucket)
  end
end
