# lib/tasks/slo4home_taxonomy.rake
#
# Conform the `cases` tenant to SLO for HOME's case-file taxonomy using OSCaR's
# CustomField configuration layer. CONFIGURATION, NOT CODE: zero net-new models
# or migrations. Source of truth = "File organization (1).pdf"; mapping rules in
# DATA-MODEL.md; field-shape contract in NOTES.md (Session 6, Step 1 findings).
#
#   slo4home:seed_taxonomy   -> create/upsert the 15 custom-field forms
#   (demo family lives in a separate task added later)
#
# Idempotent: upsert keyed on (entity_type, form_title). Reruns never duplicate;
# if a form's field definition changes, the fields are updated in place. Runs
# INSIDE the tenant (rake/runner default to the public schema otherwise).
#
# Override the tenant with TENANT=... (default: cases).

namespace :slo4home do
  desc 'Seed SLO for HOME custom-field forms (Family + Client) into the tenant. Idempotent.'
  task seed_taxonomy: :environment do
    tenant = ENV['TENANT'] || 'cases'

    # --- field builders -------------------------------------------------------
    # mk: a non-file field. select/radio-group/checkbox-group pass values: %w[...].
    mk = lambda do |type, label, opts = {}|
      h = { 'type' => type, 'label' => label }
      h['required'] = true            if opts[:required]
      h['placeholder'] = opts[:placeholder] if opts[:placeholder]
      h['values'] = opts[:values].map { |v| { 'label' => v, 'value' => v } } if opts[:values]
      h
    end
    # file: name must contain a hyphen and be unique within the form (idx).
    filef = lambda do |label, idx, opts = {}|
      h = { 'type' => 'file', 'label' => label, 'name' => "file-#{idx}" }
      h['multiple'] = true if opts[:multiple]
      h['required'] = true if opts[:required]
      h
    end
    util_status = %w[Active Pending Disconnected N/A]

    # --- FAMILY-level forms ---------------------------------------------------
    family_forms = [
      { entity_type: 'Family', form_title: 'Family Summary', fields: [
        mk.call('textarea', 'Wellness Concerns - READ FIRST before contacting family'),
        mk.call('textarea', 'Family History'),
        mk.call('textarea', 'Family Plan and Goals'),
        mk.call('text',     'Primary Phone'),
        mk.call('text',     'Email'),
        mk.call('text',     'WhatsApp'),
        mk.call('textarea', 'Mailing Address'),
        mk.call('textarea', 'Emergency Contacts (name / relationship / phone)')
      ] },
      { entity_type: 'Family', form_title: 'Housing', fields: [
        filef.call('Lease', 1, multiple: true),
        mk.call('text', 'Gas - Provider'),         mk.call('text', 'Gas - Account #'),         mk.call('select', 'Gas - Status', values: util_status),
        mk.call('text', 'Electricity - Provider'), mk.call('text', 'Electricity - Account #'), mk.call('select', 'Electricity - Status', values: util_status),
        mk.call('text', 'Water - Provider'),       mk.call('text', 'Water - Account #'),       mk.call('select', 'Water - Status', values: util_status),
        mk.call('text', 'Trash - Provider'),       mk.call('text', 'Trash - Account #'),       mk.call('select', 'Trash - Status', values: util_status),
        mk.call('text', 'Phone - Provider'),       mk.call('text', 'Phone - Account #'),       mk.call('select', 'Phone - Status', values: util_status),
        mk.call('text', 'Internet - Provider'),    mk.call('text', 'Internet - Account #'),    mk.call('select', 'Internet - Status', values: util_status)
      ] },
      { entity_type: 'Family', form_title: 'Income', fields: [
        mk.call('textarea', 'Income Sources'),
        mk.call('number',   'Monthly Household Income (USD)'),
        mk.call('textarea', 'Income Notes')
      ] },
      { entity_type: 'Family', form_title: 'Benefits', fields: [
        mk.call('textarea', 'Benefits Received'),
        mk.call('date',     'Next Recertification Date'),
        mk.call('textarea', 'Recertification Steps')
      ] },
      { entity_type: 'Family', form_title: 'Health (Family)', fields: [
        mk.call('textarea', 'Severe Health Concerns - ALERT'),
        filef.call('Power of Attorney Documents', 1, multiple: true),
        mk.call('textarea', 'General Health Notes')
      ] },
      { entity_type: 'Family', form_title: 'Immigration', fields: [
        mk.call('text',     'Immigration Status'),
        filef.call('Immigration Documents', 1, multiple: true),
        mk.call('textarea', 'Applications and Milestones')
      ] },
      { entity_type: 'Family', form_title: 'Vehicle', fields: [
        mk.call('text', 'Make / Model / Year'),
        mk.call('text', 'License Plate'),
        mk.call('text', 'Insurance Provider'),
        mk.call('date', 'Registration Expiry')
      ] }
    ]

    # --- CLIENT-level forms (member-type prefix signals who each applies to) ---
    client_forms = [
      { entity_type: 'Client', form_title: 'Member: Wellness & Goals', fields: [
        mk.call('textarea', 'Wellness Concerns - READ FIRST'),
        mk.call('textarea', 'Individual Summary and Goals')
      ] },
      { entity_type: 'Client', form_title: 'Member: Identity Documents', fields: [
        filef.call("Driver's License / State ID (adult)", 1),
        filef.call('Passport / Entry Documents', 2, multiple: true)
      ] },
      { entity_type: 'Client', form_title: 'Member: Health', fields: [
        filef.call('Insurance Card', 1),
        mk.call('textarea', 'Mental Health Needs'),
        mk.call('text',     'Mental Health Emergency Contact (EMERGENCIES ONLY - sensitive)'),
        mk.call('text',     'Primary Care Provider'),
        mk.call('textarea', 'Specialists'),
        mk.call('text',     'IHSS'),
        mk.call('textarea', 'Community Supports'),
        filef.call('Immunization Records (child)', 2, multiple: true)
      ] },
      { entity_type: 'Client', form_title: 'Adult: Employment', fields: [
        mk.call('textarea', 'Current Employment'),
        mk.call('textarea', 'Individual Assessment and Plan'),
        filef.call('Resume', 1),
        mk.call('textarea', 'Vocational Rehabilitation'),
        mk.call('textarea', 'Social Services Employment Plan'),
        mk.call('textarea', 'Community Employment Supports'),
        mk.call('textarea', 'Volunteer Work')
      ] },
      { entity_type: 'Client', form_title: 'Adult: Education', fields: [
        mk.call('textarea', 'ESL / English Classes / Tutoring'),
        mk.call('textarea', 'Vocational Training'),
        mk.call('textarea', 'GED / College Classes'),
        mk.call('textarea', 'Financial Aid')
      ] },
      { entity_type: 'Client', form_title: 'Child: Education', fields: [
        mk.call('text',     'Current School'),
        mk.call('text',     'Transportation'),
        filef.call('School Records', 1, multiple: true),
        filef.call('IEP / Accommodations (FLAG)', 2, multiple: true),
        mk.call('textarea', 'IEP / Accommodations Notes'),
        mk.call('textarea', 'Disciplinary Issues'),
        mk.call('textarea', 'Extracurriculars'),
        mk.call('textarea', 'Enrollment Dates')
      ] },
      { entity_type: 'Client', form_title: 'Child: Childcare', fields: [
        mk.call('text',     'Childcare Provider'),
        mk.call('text',     'Schedule'),
        mk.call('textarea', 'Childcare Notes')
      ] },
      { entity_type: 'Client', form_title: 'Member: Benefits', fields: [
        mk.call('textarea', 'Benefits / IHSS / Programs'),
        mk.call('textarea', 'Benefit Notes')
      ] }
    ]

    forms = family_forms + client_forms

    Apartment::Tenant.switch(tenant) do
      ngo = (Organization.find_by(short_name: tenant).try(:full_name).presence) || 'SLO for HOME'
      created = updated = unchanged = 0
      failures = []

      forms.each do |spec|
        cf = CustomField.find_or_initialize_by(entity_type: spec[:entity_type], form_title: spec[:form_title])
        cf.ngo_name = ngo
        begin
          if cf.new_record?
            cf.fields = spec[:fields]
            cf.save!
            created += 1
            puts "  + #{spec[:entity_type]} / #{spec[:form_title]}  (#{spec[:fields].size} fields)"
          elsif cf.fields != spec[:fields]
            cf.fields = spec[:fields]
            cf.save!
            updated += 1
            puts "  ~ #{spec[:entity_type]} / #{spec[:form_title]}  (fields updated)"
          else
            unchanged += 1
            puts "  = #{spec[:entity_type]} / #{spec[:form_title]}"
          end
        rescue => e
          failures << "#{spec[:entity_type]} / #{spec[:form_title]}: #{e.message} #{cf.errors.full_messages.join('; ')}"
          puts "  ! FAILED #{spec[:entity_type]} / #{spec[:form_title]}: #{e.message}"
        end
      end

      puts "\nslo4home:seed_taxonomy [tenant=#{tenant}, ngo=#{ngo.inspect}]: " \
           "#{created} created, #{updated} updated, #{unchanged} unchanged, #{failures.size} failed (of #{forms.size})."
      unless failures.empty?
        puts "FAILURES:"
        failures.each { |f| puts "  - #{f}" }
        abort 'slo4home:seed_taxonomy had failures (see above).'
      end
    end
  end

  desc 'Seed synthetic SLO for HOME demo households (10 families, mixed compositions) with sample values, enrollments + trackings. Idempotent.'
  task seed_demo_family: :environment do
    tenant = ENV['TENANT'] || 'cases'

    Apartment::Tenant.switch(tenant) do
      admin = User.order(:id).first
      abort "No User in tenant '#{tenant}'. Create the dev admin first." if admin.nil?

      # Upsert a filled custom form on an entity (idempotent by custom_field + entity).
      fill = lambda do |entity, entity_type, form_title, props|
        cf = CustomField.find_by(entity_type: entity_type, form_title: form_title)
        if cf.nil?
          puts "    (skip; form not found: #{entity_type} / #{form_title})"
          next
        end
        cfp = CustomFieldProperty.find_or_initialize_by(
          custom_field_id: cf.id,
          custom_formable_type: entity.class.name,
          custom_formable_id: entity.id
        )
        cfp.properties = props
        cfp.save!
        puts "    filled #{entity_type} / #{form_title} (#{props.size} values)"
      end

      # Enroll a client in a program (idempotent) + optionally one tracking entry.
      enroll = lambda do |client, program_name, enroll_date, props, tracking_props = nil|
        ps = ProgramStream.find_by(name: program_name)
        if ps.nil?
          puts "    (skip enroll; program not found: #{program_name})"
          next
        end
        ce = ClientEnrollment.find_or_initialize_by(client_id: client.id, program_stream_id: ps.id)
        ce.assign_attributes(status: 'Active', enrollment_date: enroll_date, properties: props)
        ce.save!
        if tracking_props && (tr = ps.trackings.first)
          cet = ClientEnrollmentTracking.find_or_initialize_by(client_enrollment_id: ce.id, tracking_id: tr.id)
          cet.properties = tracking_props
          cet.save!
          puts "    enrolled #{client.given_name} -> #{program_name} (+1 tracking)"
        else
          puts "    enrolled #{client.given_name} -> #{program_name}"
        end
      end

      # --- Family (SYNTHETIC) ---
      fam = Family.find_or_initialize_by(code: 'SLO-DEMO-1')
      fam.assign_attributes(
        name: 'Hassan Family (DEMO)',
        family_type: 'kinship',
        address: '123 Olive St, San Luis Obispo, CA 93401',
        caregiver_information: 'Synthetic demo household for the SLO for HOME walkthrough.',
        case_history: 'Resettled to SLO County in 2024. SYNTHETIC DATA ONLY.',
        # native counter/summary fields so the Family profile reads completely
        male_adult_count: 1, female_adult_count: 1,
        male_children_count: 0, female_children_count: 1,
        household_income: 3200, dependable_income: true
      )
      fam.save!
      puts "Family: #{fam.name} (id=#{fam.id}, code=#{fam.code})"

      fill.call(fam, 'Family', 'Family Summary', {
        'Wellness Concerns - READ FIRST before contacting family' => 'Prefer WhatsApp; father works day shifts. Use Dari interpreter for calls.',
        'Family History' => 'Resettled 2024 from Afghanistan (synthetic). Two adults, one school-age child.',
        'Family Plan and Goals' => 'Stable housing, adult employment, child enrolled and supported in school.',
        'Primary Phone' => '(805) 555-0142',
        'Email' => 'hassan.demo@example.org',
        'WhatsApp' => '+1 805 555 0142',
        'Mailing Address' => '123 Olive St, San Luis Obispo, CA 93401',
        'Emergency Contacts (name / relationship / phone)' => 'Sara Ahmadi (cousin) - (805) 555-0199'
      })
      fill.call(fam, 'Family', 'Housing', {
        'Gas - Provider' => 'SoCalGas', 'Gas - Account #' => 'GA-883201', 'Gas - Status' => 'Active',
        'Electricity - Provider' => 'PG&E', 'Electricity - Account #' => 'PGE-771044', 'Electricity - Status' => 'Active',
        'Internet - Provider' => 'Spectrum', 'Internet - Status' => 'Pending'
      })
      fill.call(fam, 'Family', 'Immigration', {
        'Immigration Status' => 'Asylee (synthetic)',
        'Applications and Milestones' => 'I-485 adjustment filed 2025-02; biometrics complete; EAD renewed.'
      })

      # --- Members (SYNTHETIC) ---
      members = [
        { given: 'Yusuf', last: 'Hassan', gender: 'male',   dob: Date.new(1986, 4, 12), kind: :adult },
        { given: 'Amina', last: 'Hassan', gender: 'female', dob: Date.new(1990, 9, 3),  kind: :adult },
        { given: 'Layla', last: 'Hassan', gender: 'female', dob: Date.new(2015, 1, 20), kind: :child }
      ]
      clients = {}

      members.each do |m|
        c = Client.find_or_initialize_by(given_name: m[:given], family_name: m[:last])
        c.assign_attributes(gender: m[:gender], date_of_birth: m[:dob], current_address: '123 Olive St, San Luis Obispo, CA 93401')
        c.users = [admin] if c.users.empty?
        c.save!
        clients[m[:given]] = c
        Case.create!(family: fam, client: c) unless Case.where(family_id: fam.id, client_id: c.id).exists?
        puts "  Member: #{c.given_name} #{c.family_name} (id=#{c.id}, dob=#{m[:dob]}, #{m[:kind]})"

        fill.call(c, 'Client', 'Member: Wellness & Goals', {
          'Wellness Concerns - READ FIRST' => (m[:kind] == :child ? 'Shy with new adults; needs a familiar staff member present.' : 'Comfortable in English for daily tasks; prefers Dari for complex topics.'),
          'Individual Summary and Goals' => (m[:kind] == :child ? 'Adjusting to 4th grade; goal: reading support and friendships.' : 'Goal: stable employment and community connections.')
        })
        fill.call(c, 'Client', 'Member: Health', {
          'Mental Health Needs' => 'No acute needs noted (synthetic).',
          'Primary Care Provider' => 'SLO Community Health Center',
          'Community Supports' => 'Local faith community; neighboring family.'
        })

        if m[:kind] == :adult
          fill.call(c, 'Client', 'Adult: Employment', {
            'Current Employment' => (m[:given] == 'Yusuf' ? 'Part-time warehouse associate.' : 'Seeking employment; prior experience as a teacher.'),
            'Individual Assessment and Plan' => 'ESL plus resume workshop; job-readiness sessions ongoing.',
            'Community Employment Supports' => 'Workforce center; volunteer mentor.'
          })
          fill.call(c, 'Client', 'Adult: Education', {
            'ESL / English Classes / Tutoring' => 'Enrolled in Level 2 ESL at Cuesta College (synthetic).'
          })
        else
          fill.call(c, 'Client', 'Child: Education', {
            'Current School' => 'Hawthorne Elementary (synthetic)',
            'Transportation' => 'District bus, Route 5',
            'Disciplinary Issues' => 'None.',
            'Extracurriculars' => 'After-school reading club.',
            'Enrollment Dates' => 'Enrolled 2024-09-03.'
          })
          fill.call(c, 'Client', 'Child: Childcare', {
            'Childcare Provider' => 'After-school program at the YMCA (synthetic).',
            'Schedule' => 'Mon-Fri 3-5pm.'
          })
        end
      end

      # --- Program enrollments + sample trackings (the resettlement "flows") ---
      y = clients['Yusuf']
      a = clients['Amina']
      l = clients['Layla']

      enroll.call(y, 'Housing', Date.new(2024, 9, 15), {
        'Move-in Date' => '2024-09-15', 'Housing Type' => 'Apartment',
        'Address' => '123 Olive St, San Luis Obispo, CA 93401',
        'Monthly Rent (USD)' => '1800', 'Lease End Date' => '2025-09-14'
      }, { 'Housing Status' => 'Stable', 'Rent Paid This Month' => 'Yes', 'Notes' => 'On time; settling in well.' })
      enroll.call(y, 'Employment', Date.new(2024, 11, 1), {
        'Work Authorization' => 'EAD', 'Job-Readiness Stage' => 'Placed', 'Target Sector' => 'Warehouse / Logistics'
      }, { 'Status' => 'Employed', 'Employer' => 'Central Coast Logistics', 'Hours per Week' => '32', 'Hourly Wage (USD)' => '19', 'Notes' => 'Part-time; seeking full-time.' })
      enroll.call(y, 'Immigration / Legal', Date.new(2024, 9, 20), {
        'Current Status' => 'Asylee', 'Attorney or Representative' => 'CARECEN (pro bono)', 'Application Type' => 'Adjustment (I-485)'
      }, { 'Milestone' => 'Biometrics', 'Milestone Date' => '2025-02-10', 'Notes' => 'Biometrics complete; awaiting interview.' })
      enroll.call(y, 'Benefits', Date.new(2024, 9, 18), {
        'Benefits Enrolled' => ['CalFresh', 'Medi-Cal', 'Refugee Cash Assistance'], 'Case Number' => 'SLO-RCA-44821'
      }, { 'Benefit' => 'CalFresh', 'Next Recertification Date' => '2025-09-01', 'Status' => 'Active', 'Monthly Assistance Amount (USD)' => '540', 'Notes' => 'Recert reminder set.' })
      enroll.call(a, 'Employment', Date.new(2024, 11, 5), {
        'Work Authorization' => 'EAD', 'Job-Readiness Stage' => 'Job Search', 'Target Sector' => 'Education / Childcare'
      }, { 'Status' => 'Searching', 'Hours per Week' => '0', 'Hourly Wage (USD)' => '0', 'Notes' => 'Resume complete; applying.' })
      enroll.call(a, 'Adult Education / ESL', Date.new(2024, 10, 1), {
        'ESL Level' => 'Intermediate', 'Program or Provider' => 'Cuesta College ESL', 'Goal' => 'Advance to advanced ESL; pursue teaching credential.'
      }, { 'Attendance' => 'Regular', 'Level Change' => 'Same', 'Notes' => 'Strong progress.' })
      enroll.call(a, 'Immigration / Legal', Date.new(2024, 9, 20), {
        'Current Status' => 'Asylee', 'Attorney or Representative' => 'CARECEN (pro bono)', 'Application Type' => 'Adjustment (I-485)'
      }, { 'Milestone' => 'Filed', 'Milestone Date' => '2025-02-01', 'Notes' => 'Filed jointly with spouse.' })
      enroll.call(l, 'K-12 Education', Date.new(2024, 9, 3), {
        'School' => 'Hawthorne Elementary', 'Grade' => '4th', 'Enrollment Date' => '2024-09-03'
      }, { 'Attendance' => 'Good', 'IEP Status' => 'None', 'Concerns' => 'Reading support recommended.' })
      enroll.call(l, 'Childcare', Date.new(2024, 9, 10), {
        'Provider' => 'YMCA After-School', 'Schedule' => 'Mon-Fri 3-5pm', 'Subsidy' => 'Yes'
      }, { 'Status' => 'Active', 'Notes' => 'Transportation arranged.' })

      # --- Second synthetic household (dashboard variety) ---
      fam2 = Family.find_or_initialize_by(code: 'SLO-DEMO-2')
      fam2.assign_attributes(
        name: 'Tran Household (DEMO)', family_type: 'kinship',
        address: '88 Marsh St, San Luis Obispo, CA 93401',
        caregiver_information: 'Synthetic single-adult household.',
        case_history: 'Resettled 2025. SYNTHETIC DATA ONLY.',
        male_adult_count: 1, female_adult_count: 0, male_children_count: 0, female_children_count: 0,
        household_income: 0, dependable_income: false
      )
      fam2.save!
      tran = Client.find_or_initialize_by(given_name: 'Minh', family_name: 'Tran')
      tran.assign_attributes(gender: 'male', date_of_birth: Date.new(1979, 6, 30), current_address: '88 Marsh St, San Luis Obispo, CA 93401')
      tran.users = [admin] if tran.users.empty?
      tran.save!
      Case.create!(family: fam2, client: tran) unless Case.where(family_id: fam2.id, client_id: tran.id).exists?
      puts "Family: #{fam2.name} (id=#{fam2.id}) member Minh Tran (id=#{tran.id})"
      fill.call(tran, 'Client', 'Member: Wellness & Goals', { 'Individual Summary and Goals' => 'Recently arrived; goal: housing and employment.' })
      enroll.call(tran, 'Housing', Date.new(2025, 3, 1), {
        'Move-in Date' => '2025-03-01', 'Housing Type' => 'Shared', 'Address' => '88 Marsh St, San Luis Obispo, CA 93401', 'Monthly Rent (USD)' => '900', 'Lease End Date' => '2026-02-28'
      }, { 'Housing Status' => 'At Risk', 'Rent Paid This Month' => 'Partial', 'Notes' => 'Needs rental assistance.' })
      enroll.call(tran, 'Employment', Date.new(2025, 3, 10), {
        'Work Authorization' => 'Pending', 'Job-Readiness Stage' => 'Assessment', 'Target Sector' => 'Food Service'
      }, { 'Status' => 'In Training', 'Hours per Week' => '0', 'Hourly Wage (USD)' => '0', 'Notes' => 'ESL + job-readiness.' })
      enroll.call(tran, 'Immigration / Legal', Date.new(2025, 3, 2), {
        'Current Status' => 'Asylum seeker', 'Attorney or Representative' => 'Self', 'Application Type' => 'Asylum'
      }, { 'Milestone' => 'Filed', 'Milestone Date' => '2025-03-02', 'Notes' => 'I-589 filed.' })

      # --- Additional synthetic households for demo variety (a large family, a couple, a single elder) ---
      mk_member = lambda do |fam_obj, given, last, gender, dob, addr|
        c = Client.find_or_initialize_by(given_name: given, family_name: last)
        c.assign_attributes(gender: gender, date_of_birth: dob, current_address: addr)
        c.users = [admin] if c.users.empty?
        c.save!
        Case.create!(family: fam_obj, client: c) unless Case.where(family_id: fam_obj.id, client_id: c.id).exists?
        fill.call(c, 'Client', 'Member: Wellness & Goals', { 'Individual Summary and Goals' => 'Synthetic demo record.' })
        c
      end

      extra_households = [
        { code: 'SLO-DEMO-3', name: 'Okonkwo Family (DEMO)', addr: '47 Higuera St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 1, male_children_count: 2, female_children_count: 1 },
          members: [['Emeka', 'Okonkwo', 'male', Date.new(1982, 7, 3), :adult], ['Ngozi', 'Okonkwo', 'female', Date.new(1985, 11, 19), :adult],
                    ['Chidi', 'Okonkwo', 'male', Date.new(2012, 3, 8), :child], ['Amara', 'Okonkwo', 'female', Date.new(2014, 6, 22), :child],
                    ['Obi', 'Okonkwo', 'male', Date.new(2017, 1, 30), :child]] },
        { code: 'SLO-DEMO-4', name: 'Haddad Household (DEMO)', addr: '929 Chorro St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 1, male_children_count: 0, female_children_count: 0 },
          members: [['Sami', 'Haddad', 'male', Date.new(1990, 5, 12), :adult], ['Layal', 'Haddad', 'female', Date.new(1992, 8, 27), :adult]] },
        { code: 'SLO-DEMO-5', name: 'Pham Household (DEMO)', addr: '12 Marsh St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 0, male_children_count: 0, female_children_count: 0 },
          members: [['Bao', 'Pham', 'male', Date.new(1955, 9, 9), :adult]] },
        { code: 'SLO-DEMO-6', name: 'Al-Rashid Family (DEMO)', addr: '521 Higuera St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 1, male_children_count: 2, female_children_count: 1 },
          members: [['Khalid', 'Al-Rashid', 'male', Date.new(1980, 2, 14), :adult], ['Fatima', 'Al-Rashid', 'female', Date.new(1986, 6, 9), :adult],
                    ['Omar', 'Al-Rashid', 'male', Date.new(2011, 4, 5), :child], ['Yara', 'Al-Rashid', 'female', Date.new(2013, 12, 1), :child],
                    ['Tariq', 'Al-Rashid', 'male', Date.new(2016, 7, 19), :child]] },
        { code: 'SLO-DEMO-7', name: 'Nguyen Household (DEMO)', addr: '340 Pismo St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 0, female_adult_count: 1, male_children_count: 1, female_children_count: 1 },
          members: [['Linh', 'Nguyen', 'female', Date.new(1988, 3, 22), :adult],
                    ['Duc', 'Nguyen', 'male', Date.new(2012, 10, 10), :child], ['Kim', 'Nguyen', 'female', Date.new(2015, 5, 5), :child]] },
        { code: 'SLO-DEMO-8', name: 'Mwangi Household (DEMO)', addr: '210 Broad St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 1, male_children_count: 0, female_children_count: 0 },
          members: [['Joseph', 'Mwangi', 'male', Date.new(1991, 1, 15), :adult], ['Grace', 'Mwangi', 'female', Date.new(1994, 9, 30), :adult]] },
        { code: 'SLO-DEMO-9', name: 'Castillo Household (DEMO)', addr: '75 Buchon St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 0, female_adult_count: 1, male_children_count: 0, female_children_count: 0 },
          members: [['Rosa', 'Castillo', 'female', Date.new(1957, 11, 2), :adult]] },
        { code: 'SLO-DEMO-10', name: 'Diallo Family (DEMO)', addr: '1450 Monterey St, San Luis Obispo, CA 93401',
          counts: { male_adult_count: 1, female_adult_count: 0, male_children_count: 1, female_children_count: 1 },
          members: [['Mamadou', 'Diallo', 'male', Date.new(1983, 8, 8), :adult],
                    ['Ibrahim', 'Diallo', 'male', Date.new(2010, 2, 2), :child], ['Aissatou', 'Diallo', 'female', Date.new(2014, 11, 11), :child]] }
      ]

      extra_households.each do |h|
        f2 = Family.find_or_initialize_by(code: h[:code])
        f2.assign_attributes({ name: h[:name], family_type: 'kinship', address: h[:addr],
                               caregiver_information: 'Synthetic demo household.', case_history: 'SYNTHETIC DATA ONLY.',
                               household_income: 0, dependable_income: false }.merge(h[:counts]))
        f2.save!
        head = true
        h[:members].each do |given, last, gender, dob, kind|
          c = mk_member.call(f2, given, last, gender, dob, h[:addr])
          if kind == :adult
            if head
              enroll.call(c, 'Housing', Date.new(2025, 1, 10), { 'Move-in Date' => '2025-01-10', 'Housing Type' => 'Apartment', 'Address' => h[:addr], 'Monthly Rent (USD)' => '1500' }, { 'Housing Status' => 'Stable', 'Rent Paid This Month' => 'Yes', 'Notes' => 'Synthetic.' })
              enroll.call(c, 'Benefits', Date.new(2025, 1, 11), { 'Benefits Enrolled' => ['CalFresh', 'Medi-Cal'], 'Case Number' => "SLO-#{h[:code]}" }, { 'Benefit' => 'CalFresh', 'Status' => 'Active', 'Notes' => 'Synthetic.' })
              head = false
            end
            enroll.call(c, 'Employment', Date.new(2025, 1, 15), { 'Work Authorization' => 'EAD', 'Job-Readiness Stage' => 'Job Search' }, { 'Status' => 'Searching', 'Notes' => 'Synthetic.' })
            enroll.call(c, 'Immigration / Legal', Date.new(2025, 1, 12), { 'Current Status' => 'Refugee', 'Application Type' => 'Adjustment (I-485)' }, { 'Milestone' => 'Filed', 'Notes' => 'Synthetic.' })
          else
            enroll.call(c, 'K-12 Education', Date.new(2025, 1, 8), { 'School' => 'Local Elementary', 'Grade' => '2nd', 'Enrollment Date' => '2025-01-08' }, { 'Attendance' => 'Good', 'Notes' => 'Synthetic.' })
          end
        end
        puts "Family: #{f2.name} (id=#{f2.id}, code=#{f2.code}) members=#{h[:members].size}"
      end

      puts "\nslo4home:seed_demo_family done in tenant '#{tenant}'."
    end
  end

  desc 'Seed the 7 resettlement ProgramStreams (enrollment + exit + monthly tracking) into the tenant. Idempotent.'
  task seed_programs: :environment do
    tenant = ENV['TENANT'] || 'cases'

    # program-form field builder (same JSONB field shape as CustomField/Tracking)
    pf = lambda do |type, label, opts = {}|
      h = { 'name' => label.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, ''),
            'type' => type, 'label' => label, 'className' => 'form-control' }
      h['required'] = true if opts[:required]
      h['values'] = opts[:values].map { |v| { 'label' => v, 'value' => v } } if opts[:values]
      h
    end
    exit_form = [pf.call('date', 'Exit Date', required: true), pf.call('textarea', 'Reason for Exit')]

    programs = [
      { name: 'Housing',
        description: 'Resettlement housing placement and stability support.',
        enrollment: [
          pf.call('date', 'Move-in Date', required: true),
          pf.call('select', 'Housing Type', values: ['Apartment', 'House', 'Shared', 'Transitional']),
          pf.call('text', 'Address'),
          pf.call('number', 'Monthly Rent (USD)'),
          pf.call('date', 'Lease End Date')
        ],
        exit_program: exit_form,
        tracking: { name: 'Monthly Housing Check', fields: [
          pf.call('select', 'Housing Status', values: ['Stable', 'At Risk', 'In Transition']),
          pf.call('select', 'Rent Paid This Month', values: ['Yes', 'No', 'Partial']),
          pf.call('textarea', 'Notes')
        ] } },
      { name: 'Employment',
        description: 'Job readiness, placement, and retention support.',
        enrollment: [
          pf.call('select', 'Work Authorization', values: ['EAD', 'Pending', 'U.S. Citizen', 'LPR', 'Asylum Pending']),
          pf.call('select', 'Job-Readiness Stage', values: ['Assessment', 'Training', 'Job Search', 'Placed']),
          pf.call('text', 'Target Sector')
        ],
        exit_program: [pf.call('date', 'Exit Date', required: true), pf.call('select', 'Outcome', values: ['Employed', 'Withdrew', 'Relocated'])],
        tracking: { name: 'Employment Progress', fields: [
          pf.call('select', 'Status', values: ['Employed', 'Searching', 'In Training']),
          pf.call('text', 'Employer'),
          pf.call('number', 'Hours per Week'),
          pf.call('number', 'Hourly Wage (USD)'),
          pf.call('textarea', 'Notes')
        ] } },
      { name: 'Adult Education / ESL',
        description: 'English language learning and adult education.',
        enrollment: [
          pf.call('select', 'ESL Level', values: ['Beginner', 'Intermediate', 'Advanced']),
          pf.call('text', 'Program or Provider'),
          pf.call('textarea', 'Goal')
        ],
        exit_program: exit_form,
        tracking: { name: 'Class Progress', fields: [
          pf.call('select', 'Attendance', values: ['Regular', 'Irregular', 'Stopped']),
          pf.call('select', 'Level Change', values: ['Same', 'Advanced', 'Completed']),
          pf.call('textarea', 'Notes')
        ] } },
      { name: 'K-12 Education',
        description: 'School enrollment and academic support for children.',
        enrollment: [
          pf.call('text', 'School'),
          pf.call('text', 'Grade'),
          pf.call('date', 'Enrollment Date', required: true)
        ],
        exit_program: exit_form,
        tracking: { name: 'School Check-in', fields: [
          pf.call('select', 'Attendance', values: ['Good', 'Fair', 'Poor']),
          pf.call('select', 'IEP Status', values: ['None', 'In Process', 'Active']),
          pf.call('textarea', 'Concerns')
        ] } },
      { name: 'Immigration / Legal',
        description: 'Immigration status, applications, and legal milestones.',
        enrollment: [
          pf.call('text', 'Current Status'),
          pf.call('text', 'Attorney or Representative'),
          pf.call('select', 'Application Type', values: ['Asylum', 'Adjustment (I-485)', 'TPS', 'Work Authorization (I-765)', 'Naturalization'])
        ],
        exit_program: [pf.call('date', 'Exit Date', required: true), pf.call('text', 'Outcome')],
        tracking: { name: 'Application Milestone', fields: [
          pf.call('select', 'Milestone', values: ['Filed', 'Biometrics', 'Interview Scheduled', 'RFE', 'Approved', 'Denied']),
          pf.call('date', 'Milestone Date'),
          pf.call('textarea', 'Notes')
        ] } },
      { name: 'Benefits',
        description: 'Public benefits enrollment, recertification, and assistance tracking.',
        enrollment: [
          pf.call('checkbox-group', 'Benefits Enrolled', values: ['CalFresh', 'Medi-Cal', 'CalWORKs', 'SSI', 'Refugee Cash Assistance']),
          pf.call('text', 'Case Number')
        ],
        exit_program: exit_form,
        tracking: { name: 'Recertification & Expenses', fields: [
          pf.call('text', 'Benefit'),
          pf.call('date', 'Next Recertification Date'),
          pf.call('select', 'Status', values: ['Active', 'Pending', 'Expired']),
          pf.call('number', 'Monthly Assistance Amount (USD)'),
          pf.call('textarea', 'Notes')
        ] } },
      { name: 'Childcare',
        description: 'Childcare placement and subsidy support.',
        enrollment: [
          pf.call('text', 'Provider'),
          pf.call('text', 'Schedule'),
          pf.call('select', 'Subsidy', values: ['Yes', 'No', 'Pending'])
        ],
        exit_program: exit_form,
        tracking: { name: 'Childcare Check-in', fields: [
          pf.call('select', 'Status', values: ['Active', 'Waitlist', 'Ended']),
          pf.call('textarea', 'Notes')
        ] } }
    ]

    Apartment::Tenant.switch(tenant) do
      ngo = (Organization.find_by(short_name: tenant).try(:full_name).presence) || 'SLO for HOME'
      created = updated = 0
      programs.each do |spec|
        ps = ProgramStream.find_or_initialize_by(name: spec[:name])
        was_new = ps.new_record?
        ps.assign_attributes(
          description: spec[:description],
          enrollment: spec[:enrollment],
          exit_program: spec[:exit_program],
          ngo_name: ngo,
          tracking_required: false
        )
        ps.save!
        if spec[:tracking]
          tr = ps.trackings.find_or_initialize_by(name: spec[:tracking][:name])
          tr.assign_attributes(fields: spec[:tracking][:fields], frequency: 'Monthly', time_of_frequency: 1)
          tr.save!
        end
        ps.update_column(:completed, true)
        was_new ? (created += 1) : (updated += 1)
        puts "  #{was_new ? '+' : '~'} #{spec[:name]} (enroll #{spec[:enrollment].size}, exit #{spec[:exit_program].size}, tracking #{spec[:tracking] ? 1 : 0})"
      end
      puts "slo4home:seed_programs [tenant=#{tenant}, ngo=#{ngo.inspect}]: #{created} created, #{updated} updated (of #{programs.size})."
    end
  end

  desc 'Replace the legacy child-welfare assessment Domains with SLO for HOME resettlement life-domains (English). Idempotent.'
  task seed_domains: :environment do
    tenant = ENV['TENANT'] || 'cases'

    # Build the description HTML in the same shape the original CSI domains used
    # (Goal / Sample questions / Score interpretations), but English-only and
    # framed around the household & individual self-sufficiency, not "the child".
    desc_html = lambda do |goal, questions, scores|
      q = questions.map { |x| "<li>#{x}</li>" }.join
      s = scores.each_with_index.map { |txt, i| "<p><b>#{i + 1}:</b> #{txt}</p>" }.join
      "<p><b>Goal:</b> #{goal}</p>" \
        "<p><b>Sample questions:</b></p><ul>#{q}</ul>" \
        "<hr><p><b>Score interpretations</b> (1 = in crisis &rarr; 4 = self-sufficient):</p>#{s}"
    end

    # Group names are prefixed 1.-6. so DomainGroup's default_scope(order: name)
    # renders them in this intended order; the prefix also keeps the name a stable
    # idempotency key.
    groups = [
      '1. Housing & Basic Needs',
      '2. Economic Self-Sufficiency',
      '3. Language & Education',
      '4. Health & Well-Being',
      '5. Legal & Immigration',
      '6. Community & Safety'
    ]

    domains = [
      { name: '1A', identity: 'Housing Stability', group: groups[0],
        goal: 'The household has safe, stable, affordable housing.',
        questions: ['What is the household\'s current housing situation?',
                    'Is the rent affordable relative to income?',
                    'Is the housing safe and adequate for the family size?',
                    'Is the lease or tenancy secure?'],
        scores: ['In crisis — homeless or in emergency / temporary shelter.',
                 'At risk — housed but unstable: at risk of eviction, overcrowded, or unaffordable.',
                 'Stable — safe, adequate housing with a secure lease; rent is manageable.',
                 'Self-sufficient — housing is stable, affordable, and maintained without ongoing assistance.'] },
      { name: '1B', identity: 'Food Security', group: groups[0],
        goal: 'The household has reliable access to enough nutritious food.',
        questions: ['Does the household have enough food throughout the month?',
                    'Are they enrolled in CalFresh / food assistance if eligible?',
                    'Can they shop for and prepare culturally appropriate food?'],
        scores: ['In crisis — frequently goes without enough food; relies on emergency food aid.',
                 'At risk — often runs short of food before the month\'s end.',
                 'Stable — generally has enough food, sometimes with benefit support.',
                 'Self-sufficient — reliably affords adequate, nutritious food without assistance.'] },
      { name: '2A', identity: 'Employment', group: groups[1],
        goal: 'Working-age adults are employed at a level that supports self-sufficiency.',
        questions: ['Are working-age adults employed?',
                    'Is work authorization in place?',
                    'Does the job match their skills and provide adequate hours and wages?',
                    'What are the main barriers to employment?'],
        scores: ['In crisis — no employment and significant barriers (no work authorization, no income).',
                 'At risk — underemployed or unstable work, or in active job search / training.',
                 'Stable — employed with steady hours covering most needs.',
                 'Self-sufficient — stable employment with wages meeting household needs and room to advance.'] },
      { name: '2B', identity: 'Income & Financial Management', group: groups[1],
        goal: 'The household has sufficient, well-managed income to meet its needs.',
        questions: ['Does income cover monthly expenses?',
                    'Does the household have a bank account and a budget?',
                    'Is there any savings, or mounting debt?'],
        scores: ['In crisis — income far below expenses; no banking or budgeting.',
                 'At risk — income barely covers needs; little to no savings; growing debt.',
                 'Stable — income meets expenses; basic budgeting and banking in place.',
                 'Self-sufficient — income comfortably meets needs; manages a budget and builds savings.'] },
      { name: '3A', identity: 'English Language Proficiency', group: groups[2],
        goal: 'Household members can communicate in English sufficiently for daily life and work.',
        questions: ['What is the member\'s English level (speaking and reading)?',
                    'Are they enrolled in ESL?',
                    'Can they handle daily tasks (appointments, shopping, work) in English, or do they need an interpreter?'],
        scores: ['In crisis — no functional English; fully dependent on interpreters.',
                 'At risk — very limited English; needs an interpreter for most interactions.',
                 'Stable — functional English for daily needs; building skills through ESL.',
                 'Self-sufficient — communicates effectively in English for daily life and work.'] },
      { name: '3B', identity: 'Education & Training', group: groups[2],
        goal: 'Household members are progressing toward their educational and vocational goals.',
        questions: ['Are children enrolled in and attending school?',
                    'Are adults pursuing a GED, vocational training, or credential recognition?',
                    'What are the educational goals and barriers?'],
        scores: ['In crisis — children not enrolled, or adults have no access to needed education.',
                 'At risk — inconsistent attendance or stalled progress toward goals.',
                 'Stable — children enrolled and attending; adults engaged in relevant training.',
                 'Self-sufficient — on track with educational / vocational goals; credentials recognized or in progress.'] },
      { name: '4A', identity: 'Physical Health & Healthcare Access', group: groups[3],
        goal: 'Household members are healthy and connected to the healthcare they need.',
        questions: ['Are members enrolled in health coverage (e.g., Medi-Cal)?',
                    'Do they have a primary care provider?',
                    'Are chronic conditions managed and immunizations up to date?'],
        scores: ['In crisis — untreated serious health needs; no coverage or provider.',
                 'At risk — limited access; gaps in coverage or unmanaged conditions.',
                 'Stable — enrolled in coverage with a provider; routine needs met.',
                 'Self-sufficient — members are healthy, insured, and independently manage their care.'] },
      { name: '4B', identity: 'Mental Health & Well-Being', group: groups[3],
        goal: 'Household members are coping well and have support for their emotional well-being.',
        questions: ['How are members coping with stress, trauma, or adjustment?',
                    'Are there signs of distress affecting daily functioning?',
                    'Are culturally appropriate mental-health supports and a support network available?'],
        scores: ['In crisis — severe distress or a safety concern; no support in place.',
                 'At risk — notable distress affecting daily functioning; little support.',
                 'Stable — coping adequately; supports available when needed.',
                 'Self-sufficient — emotionally resilient with strong coping skills and a support network.'] },
      { name: '5A', identity: 'Immigration Status', group: groups[4],
        goal: 'Household members have secure immigration status and are progressing on next steps.',
        questions: ['What is each member\'s current status?',
                    'Are documents in order and applications (asylum, adjustment, work authorization, reunification) on track?',
                    'Is legal representation in place?'],
        scores: ['In crisis — status in jeopardy; missed deadlines; no representation.',
                 'At risk — status temporary or uncertain; key applications pending or delayed.',
                 'Stable — status secure for now; applications filed and progressing.',
                 'Self-sufficient — stable long-term status (e.g., LPR), or a clear, on-track path with representation.'] },
      { name: '5B', identity: 'Public Benefits', group: groups[4],
        goal: 'The household receives the benefits it is eligible for and manages recertification.',
        questions: ['Which benefits is the household enrolled in (RCA, CalFresh, Medi-Cal, CalWORKs, SSI)?',
                    'Are they receiving everything they qualify for?',
                    'Are recertification dates tracked and met?'],
        scores: ['In crisis — eligible but unenrolled; no access to needed benefits.',
                 'At risk — partially enrolled; at risk of lapse or missed recertifications.',
                 'Stable — enrolled in eligible benefits; recertifications generally on time.',
                 'Self-sufficient — benefits managed independently, or no longer needed due to self-sufficiency.'] },
      { name: '6A', identity: 'Community Integration & Social Support', group: groups[5],
        goal: 'The household is building social connections and navigating the community independently.',
        questions: ['Does the household have social or community connections?',
                    'Can they use transportation and access local services?',
                    'Are they connected to a cultural or faith community?'],
        scores: ['In crisis — isolated; unable to navigate the community or access services.',
                 'At risk — few connections; heavily reliant on the case manager for navigation.',
                 'Stable — building connections; navigating most services with some support.',
                 'Self-sufficient — well-connected; navigates community and services independently.'] },
      { name: '6B', identity: 'Personal Safety', group: groups[5],
        goal: 'Household members are safe from harm at home and in the community.',
        questions: ['Are there any safety concerns at home or in the community?',
                    'Any experience of violence, exploitation, or discrimination?',
                    'Do members know how to access help in an emergency?'],
        scores: ['In crisis — an immediate safety threat (violence, exploitation, unsafe environment).',
                 'At risk — ongoing safety concerns; limited knowledge of how to get help.',
                 'Stable — generally safe; aware of emergency resources.',
                 'Self-sufficient — safe and secure; confident accessing help if needed.'] }
    ]

    Apartment::Tenant.switch(tenant) do
      keep_names = domains.map { |d| d[:name] }
      created = updated = 0

      group_records = {}
      groups.each { |gname| group_records[gname] = DomainGroup.find_or_create_by!(name: gname) }

      domains.each do |d|
        dom = Domain.find_or_initialize_by(name: d[:name])
        was_new = dom.new_record?
        dom.identity      = d[:identity]
        dom.domain_group  = group_records[d[:group]] # association assign -> counter_cache stays correct
        dom.description    = desc_html.call(d[:goal], d[:questions], d[:scores])
        dom.score_1_color = 'danger'
        dom.score_2_color = 'warning'
        dom.score_3_color = 'info'
        dom.score_4_color = 'primary'
        dom.save!
        was_new ? (created += 1) : (updated += 1)
        puts "  #{was_new ? '+' : '~'} #{d[:name]}  #{d[:identity]}  (#{d[:group]})"
      end

      # Remove any leftover legacy domains not in the resettlement set, but only
      # if nothing references them (assessments/tasks/program links). Our 1A-6B
      # names match the originals, so normally there are none.
      removed = 0
      Domain.where.not(name: keep_names).find_each do |old|
        if old.assessment_domains.exists? || old.tasks.exists? || old.domain_program_streams.exists?
          puts "  ! kept legacy #{old.name}/#{old.identity} (still referenced)"
        else
          old.destroy
          removed += 1
          puts "  - removed legacy domain #{old.name}/#{old.identity}"
        end
      end

      # Drop the now-empty legacy domain groups (the old numeric "1".."6").
      groups_removed = 0
      DomainGroup.where.not(name: groups).find_each do |g|
        if g.domains.exists?
          puts "  ! kept legacy group #{g.name} (still has domains)"
        else
          g.destroy
          groups_removed += 1
          puts "  - removed legacy group #{g.name}"
        end
      end

      puts "slo4home:seed_domains [tenant=#{tenant}]: #{created} created, #{updated} updated, " \
           "#{removed} legacy domains removed, #{groups_removed} legacy groups removed (of #{domains.size})."
    end
  end

  desc 'Run seed_taxonomy, seed_programs, seed_domains, then seed_demo_family.'
  task seed_all: %i[seed_taxonomy seed_programs seed_domains seed_demo_family]
end
