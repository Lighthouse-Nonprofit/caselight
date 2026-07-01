class AddRuntimeEnforcementSettings < ActiveRecord::Migration[7.2]
  # Runtime-enforcing security toggles (Phase 5 capstone extension) — 4 new panel controls that ENFORCE
  # at runtime, alongside the 3 existing Phase-5 authorization flags. NIST IA-2(1)/AC-7/AC-12/IA-5.
  #
  # THREE-STATE / VALUE columns on enforcement_settings, all NULLABLE, NO DB default. The NULL third
  # state is load-bearing: NULL/blank => defer to the Devise config default => byte-identical to today.
  #   require_mfa                 (boolean) NULL => only mfa_privileged? nudged (today)
  #   idle_timeout_minutes        (integer) NULL => Devise.timeout_in (30 min)
  #   lockout_max_attempts        (integer) NULL => Devise.maximum_attempts (10); model floors >= 3
  #   lockout_unlock_in_minutes   (integer) NULL => Devise.unlock_in (1 hour)
  #   password_max_age_days       (integer) NULL => no expiry (User.expire_password_after => false)
  #
  # users.password_changed_at is required by devise-security :password_expirable. We BACKFILL it for
  # every existing user (COALESCE(created_at, now())) so nobody is instantly force-expired the moment the
  # module loads — the belt paired with the User.expire_password_after=>false-when-unset suspenders.
  # A NULL password_changed_at is treated by the gem as "change required", so this backfill is a
  # SHIP-BLOCKER neutralizer, not a nicety.
  #
  # RAW SQL for the backfill (not User.update_all): decouples the migration from the application User
  # model (Tier-3 field encryption + callbacks). password_changed_at is a plaintext column filtered on a
  # plaintext column, so a set-based UPDATE is correct and callback-free.
  #
  # TENANT-SCOPED (same contract as 20260630000001): enforcement_settings AND users both live in every
  # Apartment tenant schema, so production runs `rake db:migrate` THEN `rake apartment:migrate`
  # (bootstrap.sh already does both). Ordering matters: migrate (db + apartment) BEFORE the app image that
  # enables :password_expirable goes live, so no tenant boots the new code against a column-less schema.
  def up
    add_column :enforcement_settings, :require_mfa,               :boolean
    add_column :enforcement_settings, :idle_timeout_minutes,      :integer
    add_column :enforcement_settings, :lockout_max_attempts,      :integer
    add_column :enforcement_settings, :lockout_unlock_in_minutes, :integer
    add_column :enforcement_settings, :password_max_age_days,     :integer

    add_column :users, :password_changed_at, :datetime

    # Backfill so existing users are NOT instantly expired when :password_expirable is enabled.
    say_with_time 'backfilling users.password_changed_at (COALESCE(created_at, now()))' do
      execute(<<~SQL.squish)
        UPDATE users
           SET password_changed_at = COALESCE(created_at, now())
         WHERE password_changed_at IS NULL
      SQL
    end
  end

  def down
    remove_column :users, :password_changed_at
    remove_column :enforcement_settings, :password_max_age_days
    remove_column :enforcement_settings, :lockout_unlock_in_minutes
    remove_column :enforcement_settings, :lockout_max_attempts
    remove_column :enforcement_settings, :idle_timeout_minutes
    remove_column :enforcement_settings, :require_mfa
  end
end
