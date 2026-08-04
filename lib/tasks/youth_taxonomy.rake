# Youth-flavor batch Y3 — the Youth Development taxonomy (One Community Action,
# Santa Maria: school-embedded case management + cohort curricula + victim services).
# Mirrors lib/tasks/slo4home_taxonomy.rake's patterns: idempotent find_or_initialize_by
# upserts, `mk`/`pf` field builders, `update_column(:completed, true)` on programs
# (bypasses the wizard-completion gate), TENANT env + Apartment switch.
#
# Sources: YOUTH-FLAVOR-RESEARCH.md + OCA's Casebook export (their real service types
# PV!/STH:/EYC:, school sites, cohort naming "{Curriculum} {Site} ({Term})", language
# mix incl. Mixteco/Triqui). Sensitivity is set INLINE per form — forms are designed
# homogeneous so the split-and-migrate machinery in sensitivity_classification.rake is
# never needed for this flavor.
namespace :youth do
  SCHOOL_SITES = ['Santa Maria HS', 'Ernest Righetti HS', 'Pioneer Valley HS',
                  'Delta HS', 'Fitzgerald Community School', 'Other / Not school-based'].freeze
  TERMS = ['Fall 24', 'Spring 25', 'Fall 25', 'Spring 26', 'Fall 26', 'Other'].freeze
  DELIVERY_METHODS = ['In-person', 'Phone Call', 'Text Message', 'Email', 'Videocall'].freeze

  # S1 — these seeds belong to the youth flavor ONLY. Running them on a
  # resettlement box would plant youth taxonomy in another vertical's tenant
  # (the dispatcher in flavor.rake already routes by flavor; this is the guard
  # for a hand-run rake). switch-flavor.sh flips .env BEFORE seeding, so the
  # supported flip path passes.
  def youth_flavor!
    flavor = Rails.application.config.x.flavor
    return if flavor == 'youth'
    abort "[youth] refusing: FLAVOR=#{flavor.inspect} — youth seeds run on youth boxes only."
  end

  desc 'Seed the Youth Development custom-field forms. Idempotent; sensitivity inline.'
  task seed_taxonomy: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'

    mk = lambda do |type, label, opts = {}|
      h = { 'type' => type, 'label' => label }
      h['required']    = true               if opts[:required]
      h['placeholder'] = opts[:placeholder] if opts[:placeholder]
      h['values'] = opts[:values].map { |v| { 'label' => v, 'value' => v } } if opts[:values]
      h
    end
    # file: name must contain a hyphen and be unique within the form (idx)
    filef = lambda do |label, idx, opts = {}|
      h = { 'type' => 'file', 'label' => label, 'name' => "file-#{idx}" }
      h['multiple'] = true if opts[:multiple]
      h
    end

    client_forms = [
      { entity_type: 'Client', form_title: 'Guardian & Emergency Contacts', sensitivity: 'restricted',
        fields: [
          mk.call('text', 'Guardian 1: Name', required: true),
          mk.call('text', 'Guardian 1: Relationship'),
          mk.call('text', 'Guardian 1: Phone', required: true),
          mk.call('select', 'Guardian 1: Preferred Language', values: ['English', 'Spanish', 'Mixteco', 'Zapoteco', 'Triqui', 'Purépecha', 'Other']),
          mk.call('text', 'Guardian 2: Name'),
          mk.call('text', 'Guardian 2: Relationship'),
          mk.call('text', 'Guardian 2: Phone'),
          mk.call('text', 'Emergency Contact 1: Name & Phone', required: true),
          mk.call('text', 'Emergency Contact 2: Name & Phone'),
          mk.call('textarea', 'Authorized for Pick-up (names)'),
          mk.call('radio-group', 'May Leave On Their Own (self-release)', values: %w[Yes No]),
          mk.call('textarea', 'Custody Notes (who may / may not have contact)')
        ] },
      { entity_type: 'Client', form_title: 'Youth Safety Plan', sensitivity: 'restricted',
        fields: [
          mk.call('date', 'Plan Date', required: true),
          mk.call('textarea', 'Warning Signs / Triggers'),
          mk.call('textarea', 'Coping Strategies'),
          mk.call('textarea', 'Safe People & Places'),
          mk.call('textarea', 'Professional / Crisis Contacts'),
          mk.call('select', 'Risk Context', values: ['Suicidality', 'Substance use', 'Violence exposure', 'Housing instability', 'Other']),
          mk.call('date', 'Review By')
        ] },
      { entity_type: 'Client', form_title: 'Consents & Releases', sensitivity: 'standard',
        fields: [
          mk.call('date', 'Program Participation Consent — Signed On', required: true),
          filef.call('Program Participation Consent (file)', 1),
          mk.call('radio-group', 'Media Release', values: ['Granted', 'Declined']),
          mk.call('date', 'Media Release — Signed On'),
          filef.call('Media Release (file)', 2),
          mk.call('radio-group', 'School Records Release (FERPA)', values: ['Granted', 'Declined']),
          mk.call('date', 'School Records Release — Signed On'),
          filef.call('School Records Release (file)', 3),
          mk.call('date', 'Consents Renew By (annual)')
        ] },
      { entity_type: 'Client', form_title: 'Referral & Intake', sensitivity: 'standard',
        fields: [
          mk.call('date', 'Referral Date', required: true),
          mk.call('select', 'Referred By', values: ['School staff', 'Self', 'Family', 'Peer', 'Probation', 'Community org', 'Other']),
          mk.call('textarea', 'Presenting Needs / Reason for Referral'),
          mk.call('checkbox-group', 'Immediate Needs Flagged', values: ['Food', 'Housing', 'Clothing', 'Healthcare', 'Mental health', 'Legal', 'Transportation']),
          mk.call('select', 'Intake Completed By Site', values: SCHOOL_SITES),
          # SCH3 — Aeries matching key; school-data use rides the enrollment
          # packet consent (FERPA release) + the SMJUHSD DSA before any sync runs.
          mk.call('text', 'Student ID (Aeries)')
        ] },
      { entity_type: 'Client', form_title: 'Hate Incident Record', sensitivity: 'restricted',
        fields: [
          mk.call('date', 'Incident Date', required: true),
          mk.call('select', 'Bias Category', required: true,
                  values: ['Race', 'Color', 'Disability', 'Religion', 'National origin', 'Sexual orientation', 'Gender identity']),
          mk.call('select', 'Relationship to Incident', values: ['Victim/Survivor', 'Family member', 'Bereaved family', 'Witness']),
          mk.call('checkbox-group', 'Reporting Assistance Provided', values: ['Online report', 'Police report', 'CA vs Hate', 'Declined to report']),
          mk.call('radio-group', 'Court Accompaniment Needed', values: %w[Yes No]),
          mk.call('textarea', 'Incident Narrative'),
          mk.call('textarea', 'Safety Plan Summary / Warm Handoffs')
        ] }
    ]

    family_forms = [
      { entity_type: 'Family', form_title: 'Household & Family Context', sensitivity: 'standard',
        fields: [
          mk.call('checkbox-group', 'Languages Spoken at Home', values: ['English', 'Spanish', 'Mixteco', 'Zapoteco', 'Triqui', 'Purépecha', 'Other']),
          mk.call('radio-group', 'Interpreter Needed for Family Contact', values: %w[Yes No]),
          mk.call('select', 'Parent/Guardian Program Participation', values: ['Cara y Corazón', 'Family workshops', 'None yet']),
          mk.call('radio-group', 'Bereaved Family (lost a loved one to violence)', values: %w[Yes No]),
          mk.call('textarea', 'Family Strengths & Notes')
        ] },
      # Schools batch SCH1 — the household level needs more than one form: with a
      # single Family form filled, the Add-new-form picker renders EMPTY (the
      # owner hit this on the demo box and read it as "no household forms").
      { entity_type: 'Family', form_title: 'Family Engagement Log', sensitivity: 'standard',
        fields: [
          mk.call('date', 'Contact Date'),
          mk.call('select', 'Engagement Type', values: ['Parent workshop', 'Home visit', 'Phone check-in', 'School meeting attended', 'Cara y Corazón session', 'Other']),
          mk.call('select', 'Language Used', values: ['English', 'Spanish', 'Mixteco', 'Zapoteco', 'Triqui', 'Purépecha', 'Other']),
          mk.call('textarea', 'Notes')
        ] },
      { entity_type: 'Family', form_title: 'Custody & Pickup Authorization', sensitivity: 'restricted',
        fields: [
          mk.call('textarea', 'Custody Arrangement / Court Orders on File'),
          mk.call('text', 'Authorized Pickup 1: Name & Relationship'),
          mk.call('text', 'Authorized Pickup 2: Name & Relationship'),
          mk.call('text', 'NOT Authorized (do not release to)'),
          mk.call('date', 'Last Reviewed')
        ] }
    ]

    Apartment::Tenant.switch(tenant) do
      ngo = (Organization.find_by(short_name: tenant).try(:full_name).presence) || 'One Community Action'
      created = updated = unchanged = 0
      failures = []
      (client_forms + family_forms).each do |spec|
        cf = CustomField.find_or_initialize_by(entity_type: spec[:entity_type], form_title: spec[:form_title])
        cf.ngo_name = ngo
        cf.sensitivity = spec[:sensitivity]
        if cf.new_record?
          cf.fields = spec[:fields]
          cf.save!
          created += 1
        elsif cf.fields != spec[:fields] || cf.sensitivity_changed?
          cf.fields = spec[:fields]
          cf.save!
          updated += 1
        else
          unchanged += 1
        end
      rescue StandardError => e
        failures << "#{spec[:entity_type]}/#{spec[:form_title]}: #{e.class}: #{e.message}"
      end
      puts "youth:seed_taxonomy [tenant=#{tenant}]: #{created} created, #{updated} updated, #{unchanged} unchanged."
      unless failures.empty?
        failures.each { |f| puts "  - #{f}" }
        abort 'youth:seed_taxonomy had failures (see above).'
      end
    end
  end

  desc 'Seed the Youth Development programs (multi-tracking). Idempotent.'
  task seed_programs: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'

    pf = lambda do |type, label, opts = {}|
      h = { 'name' => label.downcase.gsub(/[^a-z0-9]+/, '_').gsub(/\A_|_\z/, ''),
            'type' => type, 'label' => label, 'className' => 'form-control' }
      h['required'] = true if opts[:required]
      h['values'] = opts[:values].map { |v| { 'label' => v, 'value' => v } } if opts[:values]
      h
    end
    exit_form = [pf.call('date', 'Exit Date', required: true),
                 pf.call('select', 'Exit Reason', values: ['Completed program', 'Graduated', 'Moved', 'Disengaged', 'Referred out', 'Other']),
                 pf.call('textarea', 'Exit Notes')]

    contact_fields = lambda do |topic_values|
      [pf.call('select', 'Delivery Method', values: DELIVERY_METHODS, required: true),
       pf.call('number', 'Duration (minutes)'),
       pf.call('select', 'Topic', values: topic_values),
       pf.call('textarea', 'Notes')]
    end

    session_attendance = lambda do
      [pf.call('select', 'Session Number', values: (1..13).map(&:to_s)),
       pf.call('select', 'Attendance', values: %w[Present Absent Excused], required: true),
       pf.call('textarea', 'Session Notes')]
    end

    cohort_enrollment = [
      pf.call('select', 'School Site', values: SCHOOL_SITES, required: true),
      pf.call('select', 'Term', values: TERMS, required: true),
      pf.call('text', 'Cohort Label (optional)')
    ]

    programs = [
      { name: '¡Por Vida!',
        description: 'School-embedded case management: holistic support for students — well-being, academics, development. (PV! funder code.)',
        enrollment: [
          pf.call('select', 'School Site', values: SCHOOL_SITES, required: true),
          pf.call('select', 'Grade', values: %w[9 10 11 12 Other]),
          pf.call('textarea', 'Presenting Needs')
        ],
        trackings: [
          { name: 'Case Management Contact', frequency: 'Monthly', fields: contact_fields.call(['Check-in', 'Intervention', 'Safety', 'Academics', 'Family', 'Referral']) },
          { name: 'Mentorship Contact', frequency: nil, fields: contact_fields.call(['1:1 mentoring', 'Peer-to-peer', 'Alumni office hours']) },
          { name: 'Academic Check-in (Aeries)', frequency: 'Monthly', fields: [
            pf.call('number', 'GPA (x100, e.g. 275 = 2.75)'),
            pf.call('number', 'Credits Earned (cumulative)'),
            pf.call('select', 'A-G On Track', values: ['On track', 'At risk', 'Off track', 'N/A']),
            pf.call('number', 'School-Day Attendance % (this period)'),
            pf.call('number', 'Discipline Incidents (this period)'),
            pf.call('textarea', 'Concerns / IEP-SST Notes')
          ] },
          { name: 'Workshop / Student Engagement', frequency: nil, fields: [
            pf.call('text', 'Activity Name'),
            pf.call('select', 'Type', values: ['Workshop', 'Field trip', 'College visit', 'Leadership', 'Other']),
            pf.call('textarea', 'Notes')
          ] },
          { name: 'SMART Goals Review', frequency: nil, fields: [
            pf.call('textarea', 'Goals Reviewed / Set'),
            pf.call('select', 'Progress', values: ['On track', 'Partial', 'Stalled', 'Achieved'])
          ] }
        ] },
      { name: 'Stop The Hate',
        description: 'Victim/survivor services for hate crimes and incidents (CDSS Stop the Hate; STH funder code).',
        enrollment: [
          pf.call('select', 'Relationship to Incident', values: ['Victim/Survivor', 'Family member', 'Bereaved family', 'Witness'], required: true),
          pf.call('select', 'Referred By', values: ['Self', 'Community org', 'School', 'Law enforcement', 'Partner agency', 'Other'])
        ],
        trackings: [
          { name: 'Navigation / Case Mgmt / Referral', frequency: 'Monthly', fields: contact_fields.call(['Housing', 'Healthcare', 'Food', 'Clothing', 'Legal', 'Other navigation']) },
          { name: 'Wellness & Community Healing', frequency: nil, fields: [
            pf.call('select', 'Activity', values: ['Healing circle', 'Bereaved mothers group', 'Restorative circle', 'Listening session', 'Art & cultural work']),
            pf.call('textarea', 'Notes')
          ] },
          { name: 'Safety Planning Session', frequency: nil, fields: contact_fields.call(['Individual safety plan', 'Community safety plan']) },
          { name: 'Court / Reporting Accompaniment', frequency: nil, fields: [
            pf.call('select', 'Type', values: ['Court hearing', 'Police report', 'Online report assistance']),
            pf.call('textarea', 'Notes')
          ] }
        ] },
      { name: 'Elevate Youth Prevention',
        description: 'Substance-use prevention programming (Elevate Youth California; EYC funder code).',
        enrollment: [pf.call('select', 'School Site', values: SCHOOL_SITES)],
        trackings: [
          { name: 'Prevention Activity', frequency: nil, fields: contact_fields.call(['Convening', 'Listening session', 'Training', 'Workshop']) }
        ] },
      { name: 'R.A.I.C.E.S.',
        description: 'Youth voice & advocacy for Black, Brown and Indigenous youth (ages 12–26).',
        enrollment: [
          pf.call('select', 'Referral Form', values: ['General', 'Mentorship']),
          pf.call('textarea', 'Interests / Goals')
        ],
        trackings: [
          { name: 'Mentorship Match Contact', frequency: 'Monthly', fields: contact_fields.call(['1:1 mentoring', 'Group mentoring']) },
          { name: 'Advocacy / Youth Voice Activity', frequency: nil, fields: [
            pf.call('select', 'Activity', values: ['Advocacy', 'Artivism', 'Media literacy', 'Leadership training', 'Intergenerational healing']),
            pf.call('textarea', 'Notes')
          ] }
        ] }
    ]

    # Fixed-length cohort curricula: one program per curriculum; the cohort instance
    # lives in the enrollment's Site+Term fields ("Girasol DHS (Spring 25)" in Casebook).
    [['El Joven Noble', '12-week indigenous-based rites-of-passage youth leadership (National Compadres Network).'],
     ['Girasol', "13-week young women's rites-of-passage circle (National Compadres Network)."],
     ['Cara y Corazón', 'Family-strengthening circle for parents and caregivers (National Compadres Network).'],
     ['Nurturing Our Futures', 'Youth development cohort.'],
     ['Susto y Limpia', 'Cultural healing cohort.'],
     ['Mi Palabra', 'Youth voice & expression cohort.']].each do |name, description|
      programs << {
        name: name, description: description,
        enrollment: cohort_enrollment,
        trackings: [{ name: 'Session Attendance', frequency: 'Weekly', fields: session_attendance.call }]
      }
    end

    Apartment::Tenant.switch(tenant) do
      ngo = (Organization.find_by(short_name: tenant).try(:full_name).presence) || 'One Community Action'
      created = updated = 0
      programs.each do |spec|
        ps = ProgramStream.find_or_initialize_by(name: spec[:name])
        was_new = ps.new_record?
        ps.assign_attributes(description: spec[:description], enrollment: spec[:enrollment],
                             exit_program: exit_form, ngo_name: ngo, tracking_required: false,
                             quantity: 30)
        ps.save!
        spec[:trackings].each do |tspec|
          tr = ps.trackings.find_or_initialize_by(name: tspec[:name])
          tr.assign_attributes(fields: tspec[:fields], frequency: tspec[:frequency],
                               time_of_frequency: (tspec[:frequency] ? 1 : nil))
          tr.save!
        end
        ps.update_column(:completed, true) # bypass the wizard-completion gate (house pattern)
        was_new ? created += 1 : updated += 1
      end
      puts "youth:seed_programs [tenant=#{tenant}]: #{created} created, #{updated} updated (of #{programs.size}, multi-tracking)."
    end
  end

  desc 'Seed the Youth Development quantitative reference lists. Idempotent, additive.'
  task seed_quantitative: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'

    types = [
      { name: 'Preferred Language', allow_multiple: false,
        description: 'Language for contact with the young person themselves.',
        values: ['English', 'Spanish', 'Mixteco', 'Zapoteco', 'Triqui', 'Purépecha', 'Other'] },
      { name: 'School Site', allow_multiple: false,
        description: 'Current school of enrollment.',
        values: SCHOOL_SITES },
      { name: 'Grade Level', allow_multiple: false,
        description: 'Current grade.',
        values: ['6', '7', '8', '9', '10', '11', '12', 'Post-secondary', 'Not enrolled'] },
      { name: 'Race', allow_multiple: true,
        description: 'Self-identified; funders slice counts by this — record at intake.',
        values: ['White', 'Black or African American', 'Indigenous to the Americas',
                 'American Indian or Alaska Native', 'Asian', 'Native Hawaiian or Pacific Islander',
                 'Multi-Racial', 'Unknown', 'Declined'] },
      { name: 'Ethnicity', allow_multiple: false,
        description: 'Hispanic/Latino identification.',
        values: ['Hispanic/Latino', 'Not Hispanic/Latino', 'Unknown', 'Declined'] },
      { name: 'Poverty Level', allow_multiple: false,
        description: 'Household relative to the federal poverty level — two clicks at intake keeps funder reports complete.',
        values: ['Below', 'Above', 'Unknown'] }
    ]

    Apartment::Tenant.switch(tenant) do
      created = updated = 0
      types.each do |t|
        qt = QuantitativeType.find_or_initialize_by(name: t[:name])
        was_new = qt.new_record?
        qt.description    = t[:description]
        qt.allow_multiple = t[:allow_multiple]
        qt.save!
        was_new ? created += 1 : updated += 1
        t[:values].each { |v| qt.quantitative_cases.find_or_create_by!(value: v) }
      end
      puts "youth:seed_quantitative [tenant=#{tenant}]: #{created} created, #{updated} updated (of #{types.size})."
    end
  end

  desc 'Seed the SEL assessment domains (CASEL five + School Engagement). Idempotent; guarded reconcile.'
  task seed_domains: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'

    desc_html = lambda do |goal, questions, scores|
      q = questions.map { |x| "<li>#{x}</li>" }.join
      s = scores.each_with_index.map { |x, i| "<p><b>#{i + 1}:</b> #{x}</p>" }.join
      "<p><b>Goal:</b> #{goal}</p><p><b>Sample questions:</b></p><ul>#{q}</ul>" \
        "<hr><p><b>Score interpretations</b> (1 = emerging &rarr; 4 = consistent):</p>#{s}"
    end

    groups = ['1. Social-Emotional Learning (CASEL)', '2. School Engagement']

    scale = ['Emerging — rarely demonstrates this; needs substantial support.',
             'Developing — demonstrates with prompting and support.',
             'Demonstrating — usually demonstrates independently.',
             'Consistent — reliably demonstrates and models for peers.']

    domains = [
      { name: 'Y1', identity: 'Self-Awareness', group: groups[0],
        goal: 'The young person recognizes their emotions, values, strengths, and identity.',
        questions: ['Can they name what they are feeling and why?',
                    'Do they connect their cultural identity to their sense of self?'] },
      { name: 'Y2', identity: 'Self-Management', group: groups[0],
        goal: 'The young person regulates emotions and behavior and works toward goals.',
        questions: ['How do they handle frustration or conflict?',
                    'Are they setting and following through on goals (SMART goals)?'] },
      { name: 'Y3', identity: 'Social Awareness', group: groups[0],
        goal: 'The young person shows empathy and perspective-taking across differences.',
        questions: ['Do they consider how others experience a situation?',
                    'How do they respond to peers from different backgrounds?'] },
      { name: 'Y4', identity: 'Relationship Skills', group: groups[0],
        goal: 'The young person builds and keeps healthy, supportive relationships.',
        questions: ['Do they have trusted adults and positive peer connections?',
                    'Can they communicate needs and resolve conflict without harm?'] },
      { name: 'Y5', identity: 'Responsible Decision-Making', group: groups[0],
        goal: 'The young person makes caring, constructive choices about behavior and safety.',
        questions: ['How do they weigh consequences (substance use, safety, school)?',
                    'Do they seek help when a decision is beyond them?'] },
      { name: 'Y6', identity: 'School Engagement', group: groups[1],
        goal: 'The young person attends, participates, and progresses toward graduation.',
        questions: ['Attendance and participation trend this period?',
                    'On track for credits / A-G / graduation?'] }
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
        dom.domain_group  = group_records[d[:group]]
        dom.description   = desc_html.call(d[:goal], d[:questions], scale)
        dom.score_1_color = 'danger'
        dom.score_2_color = 'warning'
        dom.score_3_color = 'info'
        dom.score_4_color = 'primary'
        dom.save!
        was_new ? created += 1 : updated += 1
      end

      # Reference-guarded reconcile (slo4home precedent): never touches a domain that
      # holds assessments/tasks/program links; abort loudly rather than surprise-delete
      # more than the known other-flavor set.
      removable = Domain.where.not(name: keep_names).select do |old|
        !old.assessment_domains.exists? && !old.tasks.exists? && !old.domain_program_streams.exists?
      end
      if removable.size > 15
        abort "youth:seed_domains: refusing to remove #{removable.size} unreferenced domains — inspect manually."
      end
      removed = removable.each(&:destroy).size
      groups_removed = DomainGroup.where.not(name: groups).reject { |g| g.domains.exists? }.each(&:destroy).size

      puts "youth:seed_domains [tenant=#{tenant}]: #{created} created, #{updated} updated, " \
           "#{removed} other-flavor domains removed, #{groups_removed} empty groups removed."
    end
  end

  desc 'Seed SYNTHETIC Youth Development demo records (demo boxes only). Idempotent.'
  task seed_demo_youth: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'

    Apartment::Tenant.switch(tenant) do
      admin = User.order(:id).first
      abort "No User in tenant '#{tenant}'." if admin.nil?

      fill = lambda do |entity, entity_type, form_title, props|
        cf = CustomField.find_by(entity_type: entity_type, form_title: form_title)
        next puts("    (skip; form not found: #{entity_type} / #{form_title})") if cf.nil?
        cfp = CustomFieldProperty.find_or_initialize_by(
          custom_field_id: cf.id, custom_formable_type: entity.class.name, custom_formable_id: entity.id
        )
        cfp.properties = props
        cfp.save!
      end

      enroll = lambda do |client, program_name, enroll_date, props|
        ps = ProgramStream.find_by(name: program_name)
        next nil if ps.nil?
        ce = ClientEnrollment.find_or_initialize_by(client_id: client.id, program_stream_id: ps.id)
        ce.assign_attributes(status: 'Active', enrollment_date: enroll_date, properties: props)
        ce.save!
        ce
      end

      track = lambda do |enrollment, tracking_name, entry_date, props|
        tr = enrollment.program_stream.trackings.find_by(name: tracking_name)
        next if tr.nil?
        cet = ClientEnrollmentTracking.where(client_enrollment_id: enrollment.id, tracking_id: tr.id,
                                             entry_date: entry_date).first_or_initialize
        cet.properties = props
        cet.save!
      end

      fam = Family.find_or_initialize_by(code: 'OCA-DEMO-1')
      fam.assign_attributes(name: 'Demo Familia Reyes', family_type: 'kinship',
                            address: '123 Demo St, Santa Maria, CA 93454',
                            male_adult_count: 1, female_adult_count: 1,
                            male_children_count: 1, female_children_count: 1)
      fam.save!
      fill.call(fam, 'Family', 'Household & Family Context',
                'Languages Spoken at Home' => %w[Spanish Mixteco],
                'Interpreter Needed for Family Contact' => 'Yes',
                'Parent/Guardian Program Participation' => 'Cara y Corazón')

      demo_youths = [
        ['Demo-Marisol', 'Reyes', 'female', Date.new(2009, 3, 14)],
        ['Demo-Diego', 'Reyes', 'male', Date.new(2011, 8, 2)],
        ['Demo-Yaretzi', 'Cruz', 'female', Date.new(2008, 11, 30)],
        ['Demo-Angel', 'Cruz', 'male', Date.new(2010, 5, 21)]
      ]
      youths = demo_youths.map do |given, family_name, gender, dob|
        c = Client.find_or_initialize_by(given_name: given, family_name: family_name)
        c.assign_attributes(gender: gender, date_of_birth: dob, state: 'accepted',
                            current_address: '123 Demo St, Santa Maria, CA 93454')
        c.users = [admin] if c.users.empty?
        c.save!
        Case.create!(family: fam, client: c, case_type: 'KC', start_date: Time.zone.today - 90) unless Case.where(family_id: fam.id, client_id: c.id).exists?
        c
      end

      marisol = youths[0]
      fill.call(marisol, 'Client', 'Guardian & Emergency Contacts',
                'Guardian 1: Name' => 'Demo Rosa Reyes', 'Guardian 1: Relationship' => 'Mother',
                'Guardian 1: Phone' => '(805) 555-0100', 'Guardian 1: Preferred Language' => 'Mixteco',
                'Emergency Contact 1: Name & Phone' => 'Demo Tío Marco (805) 555-0101',
                'May Leave On Their Own (self-release)' => 'Yes')
      fill.call(marisol, 'Client', 'Hate Incident Record',
                'Incident Date' => (Time.zone.today - 40).iso8601, 'Bias Category' => 'National origin',
                'Relationship to Incident' => 'Victim/Survivor',
                'Reporting Assistance Provided' => ['Online report'],
                'Court Accompaniment Needed' => 'No',
                'Incident Narrative' => 'Synthetic demo narrative.')

      if (pv = enroll.call(marisol, '¡Por Vida!', Time.zone.today - 75,
                           'School Site' => 'Delta HS', 'Grade' => '11', 'Presenting Needs' => 'Demo needs'))
        track.call(pv, 'Case Management Contact', Time.zone.today - 30,
                   'Delivery Method' => 'In-person', 'Duration (minutes)' => '45',
                   'Topic' => 'Check-in', 'Notes' => 'Synthetic demo contact.')
        track.call(pv, 'Academic Check-in (Aeries)', Time.zone.today - 21,
                   'GPA (x100, e.g. 275 = 2.75)' => '275', 'Credits Earned (cumulative)' => '140',
                   'A-G On Track' => 'At risk', 'School-Day Attendance % (this period)' => '91',
                   'Discipline Incidents (this period)' => '0', 'Concerns / IEP-SST Notes' => 'Demo.')
      end

      if (gira = enroll.call(marisol, 'Girasol', Time.zone.today - 60,
                             'School Site' => 'Delta HS', 'Term' => 'Spring 26'))
        3.times do |i|
          track.call(gira, 'Session Attendance', Time.zone.today - 42 + (i * 7),
                     'Session Number' => (i + 1).to_s, 'Attendance' => 'Present',
                     'Session Notes' => "Synthetic session #{i + 1}.")
        end
      end

      youths[1..].each_with_index do |c, i|
        enroll.call(c, 'El Joven Noble', Time.zone.today - 50,
                    'School Site' => 'Pioneer Valley HS', 'Term' => 'Spring 26')
      end

      puts "youth:seed_demo_youth [tenant=#{tenant}]: #{youths.size} synthetic youths, 1 household, enrollments + backdated trackings."
    end
  end

  desc 'Seed the SMJUHSD school sites as kind=school agencies (SCH1). Idempotent.'
  task seed_schools: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'
    schools = ['Santa Maria HS', 'Ernest Righetti HS', 'Pioneer Valley HS',
               'Delta HS', 'Fitzgerald Community School']
    Apartment::Tenant.switch(tenant) do
      created = 0
      # S2: the programs a school HOSTS — school-embedded case management plus the
      # cultura cohort curricula. Additive (never unmaps a hand-added program).
      hosted = ['¡Por Vida!'] + Cohorts::SESSION_TOTALS.keys +
               ['Cara y Corazón', 'Nurturing Our Futures', 'Susto y Limpia', 'Mi Palabra']
      hosted_ids = ProgramStream.where(name: hosted.uniq).pluck(:id)
      mapped = 0
      schools.each do |name|
        agency = Agency.where('lower(name) = ?', name.downcase).first_or_initialize(name: name)
        agency.kind = 'school'
        agency.description = 'SMJUHSD partner school site' if agency.description.blank?
        created += 1 if agency.new_record?
        agency.save!
        hosted_ids.each do |program_id|
          link = AgencyProgramStream.find_or_create_by!(agency_id: agency.id, program_stream_id: program_id)
          mapped += 1 if link.previously_new_record?
        end
      end
      puts "youth:seed_schools [tenant=#{tenant}]: #{created} created, #{schools.size - created} existing (kind=school); #{mapped} program link(s)."
    end
  end

  desc 'Link youths to their kind=school agency from School Site values (SCH4). Idempotent.'
  task link_schools_from_sites: :environment do
    youth_flavor!
    tenant = ENV['TENANT'] || 'cases'
    Apartment::Tenant.switch(tenant) do
      schools = Agency.where(kind: 'school').index_by(&:name)
      abort 'youth:link_schools_from_sites: no kind=school agencies — run youth:seed_schools first.' if schools.empty?
      linked = 0

      # Source 1: the School Site quantitative selection (plaintext join).
      if (qt = QuantitativeType.find_by(name: 'School Site'))
        qt.quantitative_cases.each do |qc|
          agency = schools[qc.value] or next
          ClientQuantitativeCase.where(quantitative_case_id: qc.id).pluck(:client_id).each do |client_id|
            link = AgencyClient.find_or_create_by!(agency_id: agency.id, client_id: client_id)
            linked += 1 if link.previously_new_record?
          end
        end
      end

      # Source 2: cohort enrollments' 'School Site' field via the sidecar
      # (deterministic equality per seeded site name — never a ciphertext scan).
      schools.each do |name, agency|
        enrollment_ids = ClientEnrollmentSearchEntry
                         .where(field_label: 'School Site', value: name)
                         .pluck(:client_enrollment_id)
        ClientEnrollment.where(id: enrollment_ids).distinct.pluck(:client_id).each do |client_id|
          link = AgencyClient.find_or_create_by!(agency_id: agency.id, client_id: client_id)
          linked += 1 if link.previously_new_record?
        end
      end

      puts "youth:link_schools_from_sites [tenant=#{tenant}]: #{linked} new link(s)."
    end
  end

  desc 'Run all Youth Development seeds (taxonomy, programs, quantitative, domains, schools).'
  task seed_all: %i[seed_taxonomy seed_programs seed_quantitative seed_domains seed_schools]
end
