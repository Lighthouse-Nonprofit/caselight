# frozen_string_literal: true

# Bifurcation cleanup — removes ONE flavor's seeded taxonomy + synthetic demo
# records from a tenant that used to run that flavor (local dev after the Y6
# screenshot work; the demo box after landing on youth). Everything deleted here
# is re-creatable from that flavor's seed rake, so the operation is reversible
# by re-seeding (rm the flavor stamp + rerun bootstrap, or invoke the seeds).
#
# Layered guards:
#   * CONFIRM_UNSEED=1 required — this is a deliberate, destructive cleanup
#   * refuses to unseed the ACTIVE flavor (that would gut the server's own taxonomy)
#   * synthetic demo records are identified by the seed-owned family code prefix
#     (SLO-DEMO-* / OCA-DEMO-*); once they're gone, any enrollment or filled form
#     left on the flavor's programs/forms means REAL data → hard abort with the
#     TAXONOMY untouched (the always-safe demo purge may already have run)
#   * domains are never name-matched here: the ACTIVE flavor's own seed_domains
#     reconcile runs last and sweeps foreign domains that just lost their final
#     reference (plus emptied groups) — same guarded path the Y6 drill proved
namespace :flavor do
  UNSEED_MANIFESTS = {
    'resettlement' => {
      flavor: 'resettlement',
      family_code_prefix: 'SLO-DEMO-',
      programs: ['Housing', 'Employment', 'Adult Education / ESL', 'K-12 Education',
                 'Immigration / Legal', 'Benefits', 'Childcare'],
      forms: [['Family', 'Family Summary'], ['Family', 'Housing'], ['Family', 'Income'],
              ['Family', 'Benefits'], ['Family', 'Health (Family)'], ['Family', 'Immigration'],
              ['Family', 'Vehicle'],
              ['Client', 'Member: Wellness & Goals'], ['Client', 'Member: Identity Documents'],
              ['Client', 'Member: Health'], ['Client', 'Adult: Employment'],
              ['Client', 'Adult: Education'], ['Client', 'Child: Education'],
              ['Client', 'Child: Childcare'], ['Client', 'Member: Benefits']],
      quantitative: ['English Proficiency', 'Monthly Household Income Range',
                     'Public Benefits Enrolled'],
      active_domain_reconcile: 'youth:seed_domains'
    },
    'youth' => {
      flavor: 'youth',
      family_code_prefix: 'OCA-DEMO-',
      programs: ['¡Por Vida!', 'Stop The Hate', 'Elevate Youth Prevention', 'R.A.I.C.E.S.',
                 'El Joven Noble', 'Girasol', 'Cara y Corazón', 'Nurturing Our Futures',
                 'Susto y Limpia', 'Mi Palabra'],
      forms: [['Client', 'Guardian & Emergency Contacts'], ['Client', 'Youth Safety Plan'],
              ['Client', 'Consents & Releases'], ['Client', 'Referral & Intake'],
              ['Client', 'Hate Incident Record'], ['Family', 'Household & Family Context']],
      quantitative: ['Preferred Language', 'School Site', 'Grade Level', 'Race',
                     'Ethnicity', 'Poverty Level'],
      active_domain_reconcile: 'slo4home:seed_domains'
    }
  }.freeze

  def flavor_unseed!(manifest)
    abort '[unseed] set CONFIRM_UNSEED=1 to run this destructive cleanup' unless ENV['CONFIRM_UNSEED'] == '1'
    active = Rails.application.config.x.flavor
    if active == manifest[:flavor]
      abort "[unseed] refusing: #{manifest[:flavor]} is the ACTIVE flavor on this server"
    end

    tenant = ENV['TENANT'] || 'cases'
    Apartment::Tenant.switch(tenant) do
      removed = Hash.new(0)

      families = Family.where('code LIKE ?', "#{manifest[:family_code_prefix]}%").to_a
      family_ids = families.map(&:id)
      demo_clients = families.flat_map { |f| f.cases.filter_map(&:client) }.uniq.select do |c|
        c.cases.all? { |k| family_ids.include?(k.family_id) }
      end
      demo_clients.each do |c|
        c.destroy or abort "[unseed] ABORT: demo client #{c.id} refused destroy: #{c.errors.full_messages.join('; ')}"
        removed['demo clients'] += 1
      end
      families.each do |f|
        # reload: the selection pass above memoized f.cases, and restrict_with_error
        # would consult that stale, non-empty cache after the clients died
        f.reload
        f.destroy or abort "[unseed] ABORT: demo family #{f.code} refused destroy: #{f.errors.full_messages.join('; ')}"
        removed['demo families'] += 1
      end

      programs = ProgramStream.where(name: manifest[:programs]).to_a
      live = programs.sum { |ps| ps.client_enrollments.count }
      if live.positive?
        abort "[unseed] ABORT: #{live} enrollment(s) still attached to #{manifest[:flavor]} programs — real data?"
      end
      programs.each do |ps|
        ps.trackings.each(&:destroy)
        ps.destroy
        removed['programs'] += 1
      end

      manifest[:forms].each do |entity_type, form_title|
        cf = CustomField.find_by(entity_type: entity_type, form_title: form_title)
        next if cf.nil?
        if CustomFieldProperty.where(custom_field_id: cf.id).exists?
          abort "[unseed] ABORT: '#{form_title}' still has filled entries on live records — real data?"
        end
        cf.destroy
        removed['forms'] += 1
      end

      QuantitativeType.where(name: manifest[:quantitative]).find_each do |qt|
        if ClientQuantitativeCase.where(quantitative_case_id: qt.quantitative_cases.select(:id)).exists?
          abort "[unseed] ABORT: quantitative '#{qt.name}' still linked to live records — real data?"
        end
        qt.quantitative_cases.each(&:destroy)
        qt.destroy
        removed['quantitative types'] += 1
      end

      puts "[unseed] #{manifest[:flavor]} removed from tenant=#{tenant}: " +
           removed.map { |k, v| "#{v} #{k}" }.join(', ')
    end

    reconcile = manifest[:active_domain_reconcile]
    abort "[unseed] unknown reconcile task #{reconcile.inspect}" unless Rake::Task.task_defined?(reconcile)
    Rake::Task[reconcile].reenable
    Rake::Task[reconcile].invoke
  end

  desc 'Remove the RESETTLEMENT taxonomy + demo data from this tenant (run on a youth box). CONFIRM_UNSEED=1 required.'
  task unseed_resettlement: :environment do
    flavor_unseed!(UNSEED_MANIFESTS['resettlement'])
  end

  desc 'Remove the YOUTH taxonomy + demo data from this tenant (run on a resettlement box). CONFIRM_UNSEED=1 required.'
  task unseed_youth: :environment do
    flavor_unseed!(UNSEED_MANIFESTS['youth'])
  end
end
