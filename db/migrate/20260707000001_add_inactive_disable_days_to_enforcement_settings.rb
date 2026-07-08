# Phase 6 (AC-2(3)) — per-tenant threshold for automatic disabling of inactive accounts.
# NULLABLE three-state like every EnforcementSetting column: NULL => feature OFF (report-only),
# a value => accounts idle longer than N days are disabled by rake accounts:disable_inactive.
# Tenant-scoped table: run db:migrate AND apartment:migrate.
class AddInactiveDisableDaysToEnforcementSettings < ActiveRecord::Migration[7.2]
  def change
    add_column :enforcement_settings, :inactive_disable_days, :integer, null: true
  end
end
