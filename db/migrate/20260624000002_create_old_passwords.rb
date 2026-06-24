class CreateOldPasswords < ActiveRecord::Migration[7.1]
  # devise-security :password_archivable history table — FedRAMP IA-5 (password reuse prohibition).
  # Tenant-scoped (it archives per-user passwords), so production applies it in every tenant schema
  # via `rake apartment:migrate` alongside the shared `rake db:migrate` (bootstrap.sh runs both).
  def change
    create_table :old_passwords do |t|
      t.string     :encrypted_password, null: false
      t.string     :password_salt
      t.references :password_archivable, polymorphic: true, null: false
      t.datetime   :created_at
    end
  end
end
