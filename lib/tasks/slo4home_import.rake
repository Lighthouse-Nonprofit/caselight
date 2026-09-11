# frozen_string_literal: true

# SLO for HOME intake import.
#
# Consumes the CLEAN INTERMEDIATE JSON produced from the org's working spreadsheet by the
# owner-side parser (owner repo: `slo_parse.py`). The split is deliberate: the workbook is a
# living, human-maintained document with merged cells, group-header rows and free text, so the
# messy parsing is done once, OFF the box, and reviewed before anything is written. This task
# only ever sees clean, explicit records.
#
# CONFIGURATION, NOT CODE: every value lands on an existing `CustomField` form seeded by
# slo4home:seed_taxonomy, or on a native Family/Client/Case column. Zero net-new models.
# Run `slo4home:seed_taxonomy` FIRST — this task refuses to invent a form it cannot find.
#
# CMIA ROUTING (the part to not get wrong): the two health columns go ONLY to forms whose
# sensitivity is `emergency_only` —
#   physical_health_needs -> 'Confidential Health Information'      (emergency_only)
#   mental_health_needs   -> 'Member: Mental Health (EMERGENCIES ONLY)' (emergency_only)
# The task VERIFIES that sensitivity at run time and aborts rather than writing medical
# information onto a `standard` surface.
#
# Idempotent: keyed on Family#code / Client#code (plain columns). Names are NOT usable as keys —
# they are deterministically encrypted, and 49 of 52 members in the source have only a given name.
#
# Usage:
#   bundle exec rake slo4home:import_intake SLO_IMPORT_JSON=/path/to/slo_import.json           # DRY RUN
#   bundle exec rake slo4home:import_intake SLO_IMPORT_JSON=... CONFIRM=1 ACTIVE_STAFF=<email>
# Options: TENANT (default slo4home), INCLUDE_PROSPECTIVE=1, ACTIVE_STAFF=<user email or id>
namespace :slo4home do
  desc 'Import the SLO for HOME intake JSON (families, members, custom forms). DRY RUN unless CONFIRM=1.'
  task import_intake: :environment do
    require 'json'

    path    = ENV['SLO_IMPORT_JSON'].to_s
    tenant  = ENV['TENANT'].presence || 'slo4home'
    confirm = ENV['CONFIRM'] == '1'
    include_prospective = ENV['INCLUDE_PROSPECTIVE'] == '1'

    abort 'SLO_IMPORT_JSON=<path to the parsed JSON> is required.' if path.empty?
    abort "No such file: #{path}" unless File.exist?(path)

    payload    = JSON.parse(File.read(path))
    households = payload['households'] || []
    abort 'JSON contains no households.' if households.empty?

    # A form's sensitivity is the ONLY thing standing between CMIA medical information and a
    # general-access surface, so the mapping declares what it requires and we check it.
    health_routes = {
      'physical_health_needs' => { form: 'Confidential Health Information',
                                   requires: 'emergency_only' },
      'mental_health_needs'   => { form: 'Member: Mental Health (EMERGENCIES ONLY)',
                                   requires: 'emergency_only' }
    }.freeze

    Apartment::Tenant.switch(tenant) do
      # ---- preflight -------------------------------------------------------------------
      staff = if ENV['ACTIVE_STAFF'].present?
                key = ENV['ACTIVE_STAFF']
                User.find_by(email: key) || User.find_by(id: key)
              else
                User.order(:id).first
              end
      abort "ACTIVE_STAFF #{ENV['ACTIVE_STAFF'].inspect} matched no User in tenant #{tenant}." if staff.nil?

      missing = []
      forms = {}
      lookup = lambda do |entity_type, title|
        cf = CustomField.find_by(entity_type: entity_type, form_title: title)
        missing << "#{entity_type} / #{title}" if cf.nil?
        forms[[entity_type, title]] = cf
        cf
      end
      %w[Family\ Summary Housing Immigration].each { |t| lookup.call('Family', t) }
      ['Member: Language & Communication', 'Adult: Employment', 'Adult: Education',
       'Confidential Health Information', 'Member: Mental Health (EMERGENCIES ONLY)'].each { |t| lookup.call('Client', t) }

      unless missing.empty?
        abort "Missing custom forms (run `rake slo4home:seed_taxonomy TENANT=#{tenant}` first):\n  - " + missing.join("\n  - ")
      end

      health_routes.each_value do |route|
        cf = forms[['Client', route[:form]]]
        actual = cf.respond_to?(:sensitivity) ? cf.sensitivity.to_s : ''
        next if actual == route[:requires]

        abort "REFUSING TO IMPORT: health data is routed to #{route[:form].inspect}, whose sensitivity " \
              "is #{actual.inspect} but must be #{route[:requires].inspect}. Writing CMIA medical " \
              'information to a less-restricted form would expose it to staff without clearance. ' \
              'Fix the form sensitivity (slo4home:seed_taxonomy / sensitivity:classify) and re-run.'
      end

      puts "== slo4home:import_intake ==  tenant=#{tenant}  #{confirm ? 'APPLYING' : 'DRY RUN (set CONFIRM=1 to write)'}"
      puts "   source:        #{payload['source']}"
      puts "   parsed at:     #{payload['parsed_at']}"
      puts "   case worker:   #{staff.email} (id=#{staff.id})"
      puts "   prospective:   #{include_prospective ? 'INCLUDED' : 'skipped (set INCLUDE_PROSPECTIVE=1 to import)'}"
      puts

      fill = lambda do |entity, entity_type, title, props|
        props = props.reject { |_, v| v.nil? || v.to_s.strip.empty? }
        return 0 if props.empty?

        cf = forms[[entity_type, title]]
        if confirm
          cfp = CustomFieldProperty.find_or_initialize_by(
            custom_field_id: cf.id, custom_formable_type: entity.class.name, custom_formable_id: entity.id
          )
          # MERGE, never replace: a re-import must not wipe values staff added by hand.
          cfp.properties = (cfp.properties || {}).merge(props)
          cfp.save!
        end
        props.size
      end

      slug = ->(s) { s.to_s.strip.upcase.gsub(/[^A-Z0-9]+/, '').presence || 'X' }
      txt  = lambda do |v|
        return nil if v.nil?
        return v['text'] if v.is_a?(Hash) && v.key?('text')   # unparseable date kept verbatim
        v.to_s.strip.presence
      end

      fam_created = fam_updated = cli_created = cli_updated = cases_made = fields_written = 0
      skipped = []

      households.each do |h|
        if h['prospective'] && !include_prospective
          skipped << "#{h['label']} (prospective, #{h['members'].size} member(s))"
          next
        end

        fam_code = "SLO-#{h['label'].gsub(/\s+/, '').upcase}"          # e.g. SLO-FAMILY3
        hh = h['household'] || {}
        fam = Family.find_or_initialize_by(code: fam_code)
        is_new_fam = fam.new_record?
        fam.assign_attributes(
          name: h['label'],
          # 'birth_family' is the intact-household value in Family::family_type's inclusion list
          # (emergency/kinship/foster/inactive/birth_family). A resettled family unit is not a
          # foster or kinship placement, and 'inactive' would misreport them as closed.
          family_type: h['prospective'] ? 'inactive' : 'birth_family',
          address: txt.call(hh['address'])
        )
        fam.save! if confirm
        is_new_fam ? fam_created += 1 : fam_updated += 1

        fields_written += fill.call(fam, 'Family', 'Family Summary', {
          'Primary Phone' => txt.call(hh['phone']),
          'Mailing Address' => txt.call(hh['address']),
          'Contact Preference (call or text)' => txt.call(hh['contact_preference']),
          'Support Status' => txt.call(hh['support_status'])
        })
        fields_written += fill.call(fam, 'Family', 'Immigration', {
          'Arrival Date in the US' => txt.call(hh['arrival_date'])
        })
        fields_written += fill.call(fam, 'Family', 'Housing', {
          'Last Rental Support Month' => txt.call(hh['last_rental_support_month'])
        })

        seen = Hash.new(0)
        (h['members'] || []).each do |m|
          base = slug.call(m['given_name'])
          seen[base] += 1
          # Two members of one household can share a given name; the suffix keeps the key stable
          # and unique without depending on row numbers (their sheet's rows move).
          cli_code = "#{fam_code}-#{base}#{seen[base] > 1 ? "-#{seen[base]}" : ''}"

          c = Client.find_or_initialize_by(code: cli_code)
          is_new_cli = c.new_record?
          c.assign_attributes(given_name: m['given_name'], family_name: m['family_name'].to_s)
          c.current_address = txt.call(hh['address']) if txt.call(hh['address'])
          c.users = [staff] if c.users.empty?
          c.save! if confirm
          is_new_cli ? cli_created += 1 : cli_updated += 1

          if confirm && !Case.where(family_id: fam.id, client_id: c.id).exists?
            # Client has no family_id; household membership IS the Case row.
            Case.create!(family: fam, client: c, case_type: 'EC',
                         start_date: (Date.parse(hh['arrival_date'].to_s) rescue nil) || Date.current)
            cases_made += 1
          elsif !confirm && !(c.persisted? && Case.where(family_id: fam.id, client_id: c.id).exists?)
            cases_made += 1
          end

          p = m['person'] || {}
          emp = p['employable']
          emp_text = if emp.is_a?(Hash)
                       emp['employable'].nil? ? emp['qualifier'] : [(emp['employable'] ? 'Yes' : 'No'), emp['qualifier']].compact.join(' — ')
                     else
                       txt.call(emp)
                     end

          fields_written += fill.call(c, 'Client', 'Member: Language & Communication', {
            'Primary Language' => txt.call(p['language'])
          })
          fields_written += fill.call(c, 'Client', 'Adult: Employment', {
            'Current Employment' => txt.call(p['current_job']),
            'Individual Assessment and Plan' => txt.call(p['goal_job']),
            'Community Employment Supports' => txt.call(p['services_needed_for_employment']),
            'Profession (pre-arrival)' => txt.call(p['profession']),
            'Employable?' => emp_text,
            'Employment Barriers' => txt.call(p['employment_barriers']),
            'First Job in the US' => txt.call(p['first_job'])
          })
          fields_written += fill.call(c, 'Client', 'Adult: Education', {
            'Education Background (pre-arrival)' => txt.call(p['education']),
            'Vocational Training' => txt.call(p['training_program'])
          })

          if txt.call(p['physical_health_needs'])
            fields_written += fill.call(c, 'Client', 'Confidential Health Information', {
              'Category' => 'Other confidential health',
              'Recorded On' => Date.current.to_s,
              'Confidential Notes' => txt.call(p['physical_health_needs'])
            })
          end
          if txt.call(p['mental_health_needs'])
            fields_written += fill.call(c, 'Client', 'Member: Mental Health (EMERGENCIES ONLY)', {
              'Mental Health Needs' => txt.call(p['mental_health_needs'])
            })
          end
        end
      end

      puts "families:  #{fam_created} created, #{fam_updated} matched by code"
      puts "members:   #{cli_created} created, #{cli_updated} matched by code"
      puts "cases:     #{cases_made} household links"
      puts "values:    #{fields_written} custom-form values"
      unless skipped.empty?
        puts "\nSKIPPED (#{skipped.size}):"
        skipped.each { |s| puts "  - #{s}" }
      end
      puts "\ntotals now: clients=#{Client.count} families=#{Family.count} cases=#{Case.count}"
      puts(confirm ? "\nAPPLIED." : "\nDRY RUN — nothing was written. Re-run with CONFIRM=1 to apply.")
    end
  end
end
