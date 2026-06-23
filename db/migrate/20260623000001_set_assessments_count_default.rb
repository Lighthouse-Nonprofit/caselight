class SetAssessmentsCountDefault < ActiveRecord::Migration[5.0]
  # Rails 5.0's counter_cache increment! does `value - (value_was || 0)`, which raises
  # NoMethodError ("undefined method `-' for nil") when the counter column is NULL.
  # clients.assessments_count was the one counter column without a default (Rails 4.2
  # tolerated nil counters; 5.0 does not). Default it to 0 and backfill existing NULLs.
  def up
    change_column_default :clients, :assessments_count, 0
    Client.where(assessments_count: nil).update_all(assessments_count: 0)
  end

  def down
    change_column_default :clients, :assessments_count, nil
  end
end
