# lib/tasks/sensitivity_classification.rake
#
# Phase 5.2 (NIST AC family) — classify the SLO for HOME custom-form taxonomy to the
# org-ratified per-form sensitivity level, and SPLIT the genuinely-mixed forms so the masking
# unit (custom_field_id) is homogeneous.
#
#   TENANT=cases rake sensitivity:classify
#
# Idempotent + tenant-scoped (Apartment::Tenant.switch). Override tenant with TENANT=...
#
# FAIL-LOUD on label drift (review fix): when splitting, if ANY configured move-label or
# keep-label is NOT found in the original form's seeded fields, the task RAISES — so a typo
# can never silently leave a sensitive field on a lower-sensitivity row.
#
# properties are keyed by field LABEL (PROBED + CONFIRMED on the cases tenant: every form's
# CustomFieldProperty.properties.keys match the field labels), so the value-move reads/writes
# the DECRYPTED Hash by label.
#
# RATIFIED 2026-06-26 ("split them too"): FIVE forms are split, not two. The three additional
# mixed forms (Family Summary, Health (Family), Child: Education) each mix ONE alert field with
# routine fields; splitting keeps the routine fields at their natural level and moves only the
# alert field to emergency_only — so day-to-day family contact / school info stays accessible to
# the record's authorized readers and only the alert is break-glass.
namespace :sensitivity do
  desc 'Classify SLO for HOME custom-form sensitivity + split the mixed forms. Idempotent, fail-loud.'
  task classify: :environment do
    tenant = ENV['TENANT'] || 'cases'

    std = 'standard'
    res = 'restricted'
    emg = 'emergency_only'

    # Whole-form classifications (no mixed sensitivity within the form).
    whole_form_levels = {
      ['Family', 'Housing']                    => std,
      ['Family', 'Income']                     => std,
      ['Family', 'Benefits']                   => std,
      ['Family', 'Immigration']                => res,
      ['Family', 'Vehicle']                    => std,
      ['Client', 'Member: Identity Documents'] => res,
      ['Client', 'Adult: Employment']          => std,
      ['Client', 'Adult: Education']           => std,
      ['Client', 'Child: Childcare']           => std,
      ['Client', 'Member: Benefits']           => std
    }

    Apartment::Tenant.switch(tenant) do
      classified = 0
      missing    = []

      whole_form_levels.each do |(etype, title), level|
        cf = CustomField.find_by(entity_type: etype, form_title: title)
        if cf.nil?
          missing << "#{etype} / #{title}"
          next
        end
        if cf.sensitivity != level
          cf.update_column(:sensitivity, level)
          puts "  ~ #{etype} / #{title}  -> #{level}"
        else
          puts "  = #{etype} / #{title}  (#{level})"
        end
        classified += 1
      end

      split_form = lambda do |etype, original_title, keep_level, keep_labels, new_title, new_level, move_labels|
        original = CustomField.find_by(entity_type: etype, form_title: original_title)
        if original.nil?
          missing << "#{etype} / #{original_title}"
          next
        end

        orig_fields = original.fields || []
        orig_labels = orig_fields.map { |f| f['label'] }

        # IDEMPOTENCY: after the first run the move-labels have been moved OUT of the original
        # into new_title, so they are legitimately absent on a re-run. If the split target form
        # already exists AND the original no longer carries the move-labels, the split is done —
        # re-assert the two levels and no-op (do NOT fail-loud on the now-missing move-labels).
        existing_split = CustomField.find_by(entity_type: etype, form_title: new_title)
        if existing_split && !(move_labels - orig_labels).empty?
          original.update_column(:sensitivity, keep_level)       if original.sensitivity != keep_level
          existing_split.update_column(:sensitivity, new_level)  if existing_split.sensitivity != new_level
          puts "  = split #{etype} / #{original_title} (already split)"
          next
        end

        # FAIL-LOUD on label DRIFT (a typo / seed change) — only when the split has NOT already
        # happened, so a missing label can never silently leave a sensitive value behind.
        unknown = (keep_labels + move_labels) - orig_labels
        raise "sensitivity:classify ABORT — #{etype} / #{original_title}: labels not found in seeded fields: #{unknown.inspect} (have: #{orig_labels.inspect})" if unknown.any?

        keep_fields = orig_fields.select { |f| keep_labels.include?(f['label']) }
        move_fields = orig_fields.select { |f| move_labels.include?(f['label']) }

        new_cf = CustomField.find_or_initialize_by(entity_type: etype, form_title: new_title)
        new_cf.assign_attributes(ngo_name: original.ngo_name, frequency: original.frequency, fields: move_fields)
        new_cf.sensitivity = new_level
        new_cf.save!

        original.custom_field_properties.find_each do |orig_prop|
          props = orig_prop.properties || {}
          moved = move_labels.each_with_object({}) { |label, acc| acc[label] = props[label] if props.key?(label) }
          next if moved.empty?

          new_prop = CustomFieldProperty.find_or_initialize_by(
            custom_field_id:      new_cf.id,
            custom_formable_type: orig_prop.custom_formable_type,
            custom_formable_id:   orig_prop.custom_formable_id
          )
          new_prop.properties = (new_prop.properties || {}).merge(moved)
          new_prop.save!

          remaining = props.reject { |k, _| move_labels.include?(k) }
          if remaining == props
            # nothing to strip
          elsif remaining.empty? && keep_fields.empty?
            orig_prop.destroy
          else
            orig_prop.update!(properties: remaining)
          end
        end

        original.update!(fields: keep_fields) if original.fields != keep_fields
        original.update_column(:sensitivity, keep_level) if original.sensitivity != keep_level
        classified += 2
        puts "  / split #{etype} / #{original_title} -> [#{original_title} (#{keep_level}) | #{new_title} (#{new_level})]"
      end

      # --- The two originally-named mixed forms ---
      split_form.call(
        'Client',
        'Member: Wellness & Goals', std, ['Individual Summary and Goals'],
        'Member: Wellness Concerns - READ FIRST', emg, ['Wellness Concerns - READ FIRST']
      )
      split_form.call(
        'Client',
        'Member: Health', res,
        ['Insurance Card', 'Primary Care Provider', 'Specialists', 'IHSS', 'Community Supports', 'Immunization Records (child)'],
        'Member: Mental Health (EMERGENCIES ONLY)', emg,
        ['Mental Health Needs', 'Mental Health Emergency Contact (EMERGENCIES ONLY - sensitive)']
      )

      # --- The three additional mixed forms (ratified 2026-06-26: "split them too") ---
      split_form.call(
        'Family',
        'Family Summary', std,
        ['Family History', 'Family Plan and Goals', 'Primary Phone', 'Email', 'WhatsApp', 'Mailing Address', 'Emergency Contacts (name / relationship / phone)'],
        'Family Summary - Wellness Alert (READ FIRST)', emg,
        ['Wellness Concerns - READ FIRST before contacting family']
      )
      split_form.call(
        'Family',
        'Health (Family)', res,
        ['Power of Attorney Documents', 'General Health Notes'],
        'Health (Family) - Severe Alert', emg,
        ['Severe Health Concerns - ALERT']
      )
      split_form.call(
        'Client',
        'Child: Education', std,
        ['Current School', 'Transportation', 'School Records', 'IEP / Accommodations Notes', 'Disciplinary Issues', 'Extracurriculars', 'Enrollment Dates'],
        'Child: Education - IEP/Accommodations (FLAG)', emg,
        ['IEP / Accommodations (FLAG)']
      )

      # --- Assessment domains (RATIFIED 2026-06-26): the three sensitive life-domains -> restricted.
      # Keyed by the domain CODE (Domain#name, e.g. '4B') — the stable identifier the org uses; the
      # descriptive identity is a drift NOTICE, not a hard gate: unlike the form splits there is no
      # value-move here (just a column set on a code-identified row), so a reworded identity is
      # cosmetic and must not block a correct, code-based classification. Fail-soft if the assessment
      # taxonomy isn't seeded in this tenant (added to `missing`, same as the forms).
      domain_levels = {
        '4B' => ['Mental Health & Well-Being', res],
        '6B' => ['Personal Safety',            res],
        '5A' => ['Immigration Status',          res]
      }
      domains_classified = 0
      domain_levels.each do |code, (expected_identity, level)|
        d = Domain.find_by(name: code)
        if d.nil?
          missing << "Domain #{code} (#{expected_identity})"
          next
        end
        if d.identity != expected_identity
          puts "  ! Domain #{code}: identity drift — expected #{expected_identity.inspect}, got #{d.identity.inspect} (classifying by code anyway)"
        end
        if d.sensitivity != level
          d.update_column(:sensitivity, level)
          puts "  ~ Domain #{code} #{d.identity}  -> #{level}"
        else
          puts "  = Domain #{code} #{d.identity}  (#{level})"
        end
        domains_classified += 1
      end

      puts "\nsensitivity:classify [tenant=#{tenant}]: #{classified} form-classifications + #{domains_classified} domain-classifications applied, #{missing.size} seed forms/domains not found."
      unless missing.empty?
        puts 'NOT FOUND (seed taxonomy not run in this tenant?):'
        missing.each { |m| puts "  - #{m}" }
      end
    end
  end
end
