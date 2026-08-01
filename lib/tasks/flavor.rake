# Youth-flavor batch Y1 — the flavored-seed dispatcher. bootstrap.sh calls these two
# entry points (stamp-gated); the FLAVOR env var (whitelisted at boot in
# config/application.rb -> config.x.flavor) picks the row.
#
# seed vs demo are SPLIT deliberately (F1): the per-flavor seed list carries taxonomy/
# programs/domains/lists + the sensitivity pass and is production-safe; demo tasks
# create SYNTHETIC records and run only where SEED_DEMO=true (the demo box) — wiring
# a combined seed_all into bootstrap would plant demo households in production data.
namespace :flavor do
  FLAVOR_SEEDS = {
    'resettlement' => {
      seed: %w[slo4home:seed_taxonomy slo4home:seed_programs slo4home:seed_domains
               slo4home:seed_quantitative slo4home:seed_countries sensitivity:classify],
      demo: %w[slo4home:seed_demo_family]
    },
    # Y3: sensitivity is set inline in the youth seeds (homogeneous forms), so no
    # separate classify pass.
    'youth' => {
      seed: %w[youth:seed_taxonomy youth:seed_programs youth:seed_quantitative youth:seed_domains
               youth:seed_schools],
      demo: %w[youth:seed_demo_youth]
    }
  }.freeze

  def flavor_entry!
    flavor = Rails.application.config.x.flavor
    entry = FLAVOR_SEEDS[flavor]
    abort "[flavor] no seed map for FLAVOR=#{flavor.inspect} — add it to FLAVOR_SEEDS" if entry.nil?
    [flavor, entry]
  end

  def invoke_in_order(task_names)
    task_names.each do |name|
      abort "[flavor] unknown rake task #{name.inspect} in FLAVOR_SEEDS" unless Rake::Task.task_defined?(name)
      puts "[flavor] invoking #{name}"
      Rake::Task[name].invoke
    end
  end

  desc 'Seed the active flavor taxonomy (production-safe; TENANT= passes through).'
  task seed: :environment do
    flavor, entry = flavor_entry!
    puts "[flavor] FLAVOR=#{flavor} seed (#{entry[:seed].size} tasks)"
    invoke_in_order(entry[:seed])
  end

  desc 'Seed the active flavor DEMO data (synthetic records — demo boxes only).'
  task seed_demo: :environment do
    flavor, entry = flavor_entry!
    puts "[flavor] FLAVOR=#{flavor} seed_demo (#{entry[:demo].size} tasks)"
    invoke_in_order(entry[:demo])
  end
end
