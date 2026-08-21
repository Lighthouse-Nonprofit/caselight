# Bifurcate note types into families (OCA request 2026-08-21): a ProgressNoteType now carries a
# `category` so the flexible note is organized as Contact / Curriculum / General rather than one flat
# list. Existing rows default to 'contact' (the seeded set is all contact-type); the seed + a
# recategorize rake set 'curriculum'/'general' where they belong. See ProgressNoteType::CATEGORIES.
class AddCategoryToProgressNoteTypes < ActiveRecord::Migration[8.0]
  def change
    add_column :progress_note_types, :category, :string, default: 'contact', null: false
  end
end
