class AddLockableToUsers < ActiveRecord::Migration[7.1]
  # Devise :lockable columns — FedRAMP AC-7 (lock an account after repeated failed sign-ins).
  # `users` is a tenant-scoped table (only Organization is excluded from Apartment), so in
  # production this lands in every tenant schema via `rake apartment:migrate` in addition to the
  # shared `rake db:migrate`. bootstrap.sh runs both.
  def change
    add_column :users, :failed_attempts, :integer, null: false, default: 0
    add_column :users, :unlock_token,    :string
    add_column :users, :locked_at,       :datetime
    add_index  :users, :unlock_token, unique: true
  end
end
