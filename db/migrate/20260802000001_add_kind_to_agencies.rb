# Schools batch SCH1 — agencies gain a generic `kind` so verticals can promote
# specific partner types to first-class surfaces (youth: kind=school gets a main
# sidebar entry + roster page; resettlement could later mark kind=funder).
# Plain string with a default, no enum constraint — the flavor seeds own the
# vocabulary, core stays vertical-neutral.
class AddKindToAgencies < ActiveRecord::Migration[8.1]
  def change
    add_column :agencies, :kind, :string, null: false, default: 'partner'
    add_index :agencies, :kind
  end
end
