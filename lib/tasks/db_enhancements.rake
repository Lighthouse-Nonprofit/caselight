namespace :db do
  desc 'Also create shared_extensions Schema'
  task :extensions => :environment  do
    # Create Schema
    ActiveRecord::Base.connection.execute 'CREATE SCHEMA IF NOT EXISTS shared_extensions;'
    # Enable Hstore
    ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS HSTORE SCHEMA shared_extensions;'
    # Enable UUID-OSSP
    ActiveRecord::Base.connection.execute 'CREATE EXTENSION IF NOT EXISTS "uuid-ossp" SCHEMA shared_extensions;'
  end
end

Rake::Task["db:create"].enhance do
  Rake::Task["db:extensions"].invoke
end

Rake::Task["db:test:purge"].enhance do
  Rake::Task["db:extensions"].invoke
end

# Rails 8's schema dumper qualifies extensions with their schema
# (enable_extension "shared_extensions.hstore"), but enable_extension does not create
# the schema itself — so `db:schema:load` against a database that skipped `db:create`
# (CI: the postgres service pre-creates the DB) needs shared_extensions to exist first.
# Prerequisite form (not a block): it must run BEFORE the load.
Rake::Task["db:schema:load"].enhance(["db:extensions"])