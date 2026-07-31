# Data-task batch D3 — quantitative types become usable ("better define quantitative
# types so they're useable"). Adds the single/multi knob and the referential integrity
# the 2016 tables never had. Data cleanup is up-only (orphans/dupes cannot be restored).
class MakeQuantitativeTypesUsable < ActiveRecord::Migration[8.1]
  def up
    add_column :quantitative_types, :allow_multiple, :boolean, null: false, default: true

    # Orphan/dupe sweep BEFORE the FKs + unique pair land (synthetic pilot data only).
    execute <<~SQL
      DELETE FROM client_quantitative_cases WHERE client_id IS NULL OR quantitative_case_id IS NULL;
      DELETE FROM client_quantitative_cases cqc
        WHERE NOT EXISTS (SELECT 1 FROM clients c WHERE c.id = cqc.client_id)
           OR NOT EXISTS (SELECT 1 FROM quantitative_cases q WHERE q.id = cqc.quantitative_case_id);
      DELETE FROM client_quantitative_cases a USING client_quantitative_cases b
        WHERE a.id > b.id AND a.client_id = b.client_id
          AND a.quantitative_case_id = b.quantitative_case_id;
      DELETE FROM quantitative_cases qc
        WHERE qc.quantitative_type_id IS NOT NULL
          AND NOT EXISTS (SELECT 1 FROM quantitative_types t WHERE t.id = qc.quantitative_type_id);
    SQL

    add_index :quantitative_cases, :quantitative_type_id, name: 'idx_quantitative_cases_type'
    add_foreign_key :quantitative_cases, :quantitative_types, on_delete: :cascade

    add_index :client_quantitative_cases, %i[client_id quantitative_case_id],
              unique: true, name: 'idx_client_quantitative_cases_pair'
    add_index :client_quantitative_cases, :quantitative_case_id, name: 'idx_client_quantitative_cases_case'
    add_foreign_key :client_quantitative_cases, :clients, on_delete: :cascade
    add_foreign_key :client_quantitative_cases, :quantitative_cases, on_delete: :cascade
  end

  def down
    remove_foreign_key :client_quantitative_cases, :quantitative_cases
    remove_foreign_key :client_quantitative_cases, :clients
    remove_index :client_quantitative_cases, name: 'idx_client_quantitative_cases_case'
    remove_index :client_quantitative_cases, name: 'idx_client_quantitative_cases_pair'
    remove_foreign_key :quantitative_cases, :quantitative_types
    remove_index :quantitative_cases, name: 'idx_quantitative_cases_type'
    remove_column :quantitative_types, :allow_multiple
  end
end
