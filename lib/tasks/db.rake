# lib/tasks/db.rake
#
# TRUTH-IN-LABELING (Phase 6): these tasks dump/restore ONLY the `public` schema — in an
# Apartment schema-per-tenant app that is the Organization/shared tables, NOT the tenant
# schemas where all client data lives. This is NOT a backup. Real backups are the inherited
# infrastructure control (encrypted EBS snapshots); the tenant-preserving migration playbook
# lives with the PG-17 migration notes. Also fixed for Rails 7 (connection_config was removed;
# these tasks raised NoMethodError since the 6.1 upgrade — they were silently broken).

namespace :db do

  desc "Dump ONLY the public schema (Organization/shared tables) to db/<app>_<env>_pg.dump. " \
       "NOT a backup: tenant schemas (all client data) are NOT included."
  task :dump => :environment do
    cmd = nil
    with_config do |app, host, db, user|
      if Rails.env.production?
        cmd = "pg_dump -n public --column-inserts -a --verbose --no-acl -h #{host} -d #{db} > #{Rails.root}/db/#{app}_#{Rails.env}_pg.dump"
      else
        cmd = "pg_dump -n public --column-inserts -a --verbose --no-acl -d #{db} > #{Rails.root}/db/#{app}_#{Rails.env}_pg.dump"
      end
    end
    puts "[db:dump] PUBLIC SCHEMA ONLY — tenant schemas are NOT included; this is not a backup."
    puts cmd
    exec cmd
  end

  desc "Update search_path to copy schema"
  task :update_search_path => :environment do
    cmd = nil
    with_config do |app, host, db, user|
      cmd = "sed 's/SET search_path =/SET search_path to cif,/' < #{Rails.root}/db/#{app}_#{Rails.env}_pg.dump > #{Rails.root}/db/#{app}_#{Rails.env}_updated_pg.dump"
    end
    puts cmd
    exec cmd
  end

  desc "Restores the public-schema dump at db/<app>_<env>_updated_pg.dump (NOT a full restore)."
  task :restore => :environment do
    cmd = nil
    with_config do |app, host, db, user|
      cmd = "psql #{db} < #{Rails.root}/db/#{app}_#{Rails.env}_updated_pg.dump"
    end
    puts cmd
    exec cmd
  end

  private

  # Rails 7: connection_config was removed (deprecated in 6.1); read the resolved db config hash.
  # `module_parent_name` replaces the removed `parent_name`.
  def with_config
    config = ActiveRecord::Base.connection_db_config.configuration_hash
    yield Rails.application.class.module_parent_name.underscore,
      config[:host],
      config[:database],
      config[:username],
      config[:password]
  end
end
