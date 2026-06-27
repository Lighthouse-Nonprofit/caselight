# lib/tasks/break_glass.rake
#
# Phase 5.4 — break-glass deploy smoke (NIST AC-3 / CM-3 deploy verification).
#
# break_glass_grants is TENANT-SCOPED (one per Apartment schema). A deploy that ran db:migrate
# but forgot apartment:migrate would leave SOME tenants without the table. The model FAILS CLOSED
# there (emergency_only stays denied, no 500) — safe but SILENT. This smoke makes the gap LOUD:
# it asserts the table in EVERY tenant and aborts (non-zero) if any is missing, so the deploy
# pipeline halts instead of shipping a tenant where break-glass can never succeed.
#
#   bundle exec rake break_glass:smoke
#
# Iterates Organization.pluck(:short_name) and switches into each schema (block form auto-resets
# even on exception) — same multi-tenant idiom as encryption.rake / slo4home_taxonomy.rake.
namespace :break_glass do
  desc 'Assert break_glass_grants exists in EVERY tenant schema; FAIL CLOSED (abort) if missing anywhere.'
  task smoke: :environment do
    tenants = Organization.pluck(:short_name)
    if tenants.empty?
      puts 'break_glass:smoke — no tenants found; nothing to assert.'
      next
    end

    missing = []
    present = 0

    tenants.each do |tenant|
      begin
        Apartment::Tenant.switch(tenant) do
          if ActiveRecord::Base.connection.table_exists?('break_glass_grants')
            present += 1
            puts "  ok  #{tenant} — break_glass_grants present"
          else
            missing << tenant
            puts "  !!  #{tenant} — break_glass_grants MISSING"
          end
        end
      rescue => e
        # A tenant we cannot even inspect is treated as missing (fail closed).
        missing << tenant
        puts "  !!  #{tenant} — could not verify (#{e.class}: #{e.message})"
      end
    end

    puts "\nbreak_glass:smoke: #{present}/#{tenants.size} tenants OK, #{missing.size} missing."
    unless missing.empty?
      abort "break_glass:smoke FAILED (fail-closed): break_glass_grants missing in tenant(s): #{missing.join(', ')}. Run `rake apartment:migrate` before relying on emergency access."
    end
  end
end
