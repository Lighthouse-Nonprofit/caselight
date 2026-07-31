# Data-task batch D4 — CA SOGI gender list. The 2016 column default was the capitalized
# string "Male": silently stamped on every record, matching NO grid filter value (the old
# filter compared 'Male'/'male' and bucketed everything else as female). Default goes to
# nil ("not stated"); legacy values fold to the lowercase tokens the new closed list uses.
class NormalizeClientGender < ActiveRecord::Migration[8.1]
  def up
    change_column_default :clients, :gender, nil
    execute "UPDATE clients SET gender = lower(gender) WHERE gender IS NOT NULL AND gender <> lower(gender)"
    execute "UPDATE clients SET gender = NULL WHERE gender = ''"
  end

  def down
    change_column_default :clients, :gender, 'Male'
  end
end
