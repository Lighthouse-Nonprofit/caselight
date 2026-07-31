# Data-task batch D1 — link partner agencies to the programs they work with
# (domain_program_streams precedent). Also drops `agencies_clients`: a dead twin of the
# real join (`agency_clients`) — zero references anywhere in app/lib/config/spec.
class CreateAgencyProgramStreams < ActiveRecord::Migration[8.1]
  def change
    create_table :agency_program_streams do |t|
      t.integer :agency_id, null: false
      t.integer :program_stream_id, null: false
      t.timestamps
      t.index %i[agency_id program_stream_id], unique: true, name: 'idx_agency_program_streams_pair'
      t.index :program_stream_id, name: 'idx_agency_program_streams_ps'
    end
    add_foreign_key :agency_program_streams, :agencies, on_delete: :cascade
    add_foreign_key :agency_program_streams, :program_streams, on_delete: :cascade

    drop_table :agencies_clients, id: :serial do |t|
      t.integer  :agency_id
      t.integer  :client_id
      t.datetime :created_at, precision: nil
      t.datetime :updated_at, precision: nil
    end
  end
end
