# frozen_string_literal: true

module Casebook
  # Persist phase of casebook:import — only ever invoked behind the triple gate
  # (CONFIRM=1 + production + explicit tenant). Every entity upserts on a
  # Casebook GUID (or a full-content key for notes), so re-running is safe.
  class Applier
    IMPORT_FORM_TITLE = 'Imported from Casebook'

    QUANTITATIVE_MAP = {
      'Primary Language' => 'Preferred Language',
      'Race' => 'Race',
      'Hispanic/Latino' => 'Ethnicity',
      'Poverty Level' => 'Poverty Level'
    }.freeze

    GENDER_MAP = { 'male' => 'male', 'female' => 'female' }.freeze

    # Casebook embeds the delivery site as an abbreviation inside case/cohort names
    # ("Girasol DHS (Spring 25)"). Map to the seeded Site names (School/Site split).
    SITE_ABBREV = {
      'delta' => 'Delta HS', 'dhs' => 'Delta HS',
      'santa maria' => 'Santa Maria HS', 'smhs' => 'Santa Maria HS',
      'ernest righetti' => 'Ernest Righetti HS', 'righetti' => 'Ernest Righetti HS', 'rhs' => 'Ernest Righetti HS',
      'pioneer valley' => 'Pioneer Valley HS', 'pvhs' => 'Pioneer Valley HS', 'pioneer' => 'Pioneer Valley HS',
      'fitzgerald' => 'Fitzgerald Community School', 'fcs' => 'Fitzgerald Community School'
    }.freeze

    def initialize(plan, active_staff: [])
      @plan = plan
      @active_staff = active_staff
      @counts = Hash.new(0)
    end

    # ALL-OR-NOTHING: seven upsert phases in one transaction. A RecordInvalid in
    # a late phase (an exit form that validates, a bad note) must not leave a
    # half-imported tenant behind — the operator fixes the mapping and re-runs.
    def apply!
      ActiveRecord::Base.transaction do
        @form = ensure_import_form!
        @import_user = ensure_users!
        @guid_clients = existing_guid_map
        clients = upsert_clients!
        upsert_families!(clients)
        enrollments = upsert_enrollments!(clients)
        upsert_exits!(enrollments)
        upsert_notes!(clients, enrollments)
        upsert_agencies!
        # Imported clients are HISTORIC/inactive (owner decision 2026-08). The KC household case
        # sets 'Active KC' on members via a callback, so force the status blank AFTER all cases
        # exist (update_all bypasses the callback; the household link via the Case is unaffected).
        Client.where(id: (@imported_client_ids || []).uniq).update_all(status: '')
      end
      @counts.sort.each { |k, v| puts "  #{k}: #{v}" }
      @counts
    end

    private

    def ensure_import_form!
      cf = CustomField.find_or_initialize_by(entity_type: 'Client', form_title: IMPORT_FORM_TITLE)
      cf.fields = [
        { name: 'casebook_person_id', type: 'text', label: 'Casebook person_id' },
        { name: 'age_at_export', type: 'text', label: 'Age at export' },
        { name: 'education', type: 'text', label: 'Education (Casebook)' },
        { name: 'birthplace', type: 'text', label: 'Birthplace (Casebook)' },
        { name: 'employment', type: 'text', label: 'Employment (Casebook)' },
        { name: 'income', type: 'text', label: 'Income (Casebook)' },
        { name: 'case_meta', type: 'textarea', label: 'Casebook case meta' }
      ].map(&:stringify_keys)
      cf.sensitivity = 'standard' if cf.respond_to?(:sensitivity=)
      cf.save!
      cf
    end

    # Staff (Assignee/Author names) become Users: active staff enabled, everyone
    # else DISABLED with a random password — authorship preserved, no door keys.
    def ensure_users!
      @users_by_name = {}
      @plan[:staff].each_key do |name|
        # parameterize collapses diacritics ("José García" and "Jose Garcia" both
        # → jose-garcia), which would silently merge two staffers' identities and
        # authorship. Keep a per-run claim on each slug and suffix collisions.
        slug = unique_staff_slug(name)
        user = User.find_or_initialize_by(email: "casebook-#{slug}@import.invalid")
        if user.new_record?
          given, family = name.split(/\s+/, 2)
          user.assign_attributes(first_name: given.to_s, last_name: family.to_s,
                                 roles: 'case worker', password: SecureRandom.hex(24))
          @counts['users created'] += 1
        end
        user.disable = !@active_staff.include?(name)
        user.save!(validate: false)
        @users_by_name[name] = user
      end
      admin = User.where(disable: false).order(:id).first || User.order(:id).first
      abort 'No usable User in tenant for record ownership.' if admin.nil?
      admin
    end

    def unique_staff_slug(name)
      @staff_slugs ||= {}
      base = name.parameterize.presence || 'staff'
      return @staff_slugs[name] if @staff_slugs.key?(name)
      slug = base
      suffix = 1
      while @staff_slugs.value?(slug)
        suffix += 1
        slug = "#{base}-#{suffix}"
      end
      @staff_slugs[name] = slug
    end

    def existing_guid_map
      CustomFieldProperty.where(custom_field_id: @form.id, custom_formable_type: 'Client')
                         .each_with_object({}) do |cfp, map|
        guid = cfp.properties['Casebook person_id']
        map[guid] = cfp.custom_formable_id if guid.present?
      end
    end

    def upsert_clients!
      out = {}
      @plan[:resolvable].each { |name, row| out[name] = build_client(name, row) }
      # Graceful collisions: create the 2nd+ same-name people as DISTINCT clients (keyed on person_id).
      # They are NOT added to the name map, so name-keyed cases/notes stay with the first twin — the
      # org splits them by hand (the audit lists the collision).
      (@plan[:collided_extra] || []).each do |row|
        build_client(row['Person Name'].to_s.strip, row)
        @counts['collided twins imported'] += 1
      end
      out
    end

    def build_client(name, row)
      guid = row['person_id'].to_s
      client = @guid_clients[guid] ? Client.find(@guid_clients[guid]) : Client.new
      given, family = split_name(name)
      # status: '' — imported clients are HISTORIC/inactive (owner decision 2026-08); leaving the
      # status blank keeps them out of the active-caseload buckets (the clients.status column
      # DEFAULTS to 'Referred', which would wrongly read as a pending intake).
      client.assign_attributes(given_name: given, family_name: family, state: 'accepted', status: '',
                               gender: GENDER_MAP[row['Sex'].to_s.strip.downcase].to_s,
                               current_address: address_line(row))
      client.users = [assignee_for(name)] if client.users.empty?
      @counts[client.new_record? ? 'clients created' : 'clients updated'] += 1
      client.save!
      fill_form(client, guid, row)
      link_quantitative(client, row)
      (@imported_client_ids ||= []) << client.id
      client
    end

    def upsert_families!(clients)
      @plan[:families].each do |case_id, fam|
        family = Family.find_or_initialize_by(code: "CB-#{case_id}")
        family.assign_attributes(name: fam[:case_name].to_s, family_type: 'kinship')
        @counts[family.new_record? ? 'families created' : 'families updated'] += 1
        family.save!
        fam[:members].filter_map { |n| clients[n] }.each do |client|
          next if Case.where(family_id: family.id, client_id: client.id).exists?
          Case.create!(family: family, client: client, case_type: 'KC', start_date: Time.zone.today)
          @counts['family links created'] += 1
        end
      end
    end

    def upsert_enrollments!(clients)
      @plan[:enrollments].each_with_object({}) do |e, out|
        client = clients[e[:person]] or next
        # Casebook case names embed the delivery site + term ("Girasol DHS (Spring 25)").
        name = e[:row]['Case Name']
        site = parse_site(name)
        term = parse_term(name)
        ce = enroll(client, e[:person], e[:program], site: site, term: term)
        out[[e[:person], e[:program], cohort_key(site, term)]] = ce if ce
      end
    end

    def cohort_key(site, term)
      [site, term].map { |v| v.to_s.strip }.reject(&:empty?).join(' · ')
    end

    def enroll(client, person, program_name, site: nil, term: nil)
      ps = ProgramStream.find_by(name: program_name)
      return nil if ps.nil?
      # OCA 2026-08: cohorts are SEPARATE — one enrollment per (client, program, cohort=Site+Term),
      # not one merged enrollment per program. A blank cohort is the single default bucket.
      ce = ClientEnrollment.find_or_initialize_by(client_id: client.id, program_stream_id: ps.id,
                                                  cohort: cohort_key(site, term))
      if ce.new_record?
        ce.enrollment_date = @plan[:note_dates].dig(person, 0) || Time.zone.today
        ce.status = 'Active'
        props = {}
        props['Site'] = site if site.present?
        props['Term'] = term if term.present?
        ce.properties = props if props.any?
        @counts['enrollments created'] += 1
        ce.save!
        # School/Site split: ¡Por Vida! is school-embedded, so a Student's delivery
        # SITE is their school of ATTENDANCE — default the client 'School' from it
        # (owner decision). Non-school sites ('Community Site'/'Other') have no
        # 'School' quantitative value, so set_school_from_site is a no-op for them.
        set_school_from_site(client, site) if site.present? && program_name == '¡Por Vida!'
      end
      ce
    end

    def upsert_exits!(enrollments)
      @plan[:exits].each do |e|
        name = e[:row] && e[:row]['Case Name']
        ce = enrollments[[e[:person], e[:program], cohort_key(parse_site(name), parse_term(name))]] or next
        next if ce.status == 'Exited'
        LeaveProgram.create!(client_enrollment_id: ce.id, program_stream_id: ce.program_stream_id,
                             exit_date: e[:exit_date] || Time.zone.today)
        ce.update_columns(status: 'Exited')
        @counts['exits created'] += 1
      end
    end

    def upsert_notes!(clients, enrollments)
      @note_types = {}
      default_type = note_type_for(IMPORT_FORM_TITLE)
      # A real Location: without one, other_location? compares nil == nil (the
      # Khmer 'Other' lookup misses) and the presence validation always fires.
      location = Location.find_or_create_by!(name: IMPORT_FORM_TITLE)
      bare = []
      @plan[:notes].each do |row|
        client = clients[row['Person Name'].to_s.strip] or next
        date = to_date(row['Contact Start Date']) || Time.zone.today
        author = @users_by_name[row['Author'].to_s.strip] || @import_user
        subject = "[Casebook] #{row['Subject'].to_s.strip}"
        narrative = row['Narrative'].to_s
        c = SubjectClassifier.classify(row['Subject'])
        # OCA 2026-08: contact-type subjects set the ProgressNote's TYPE (Phone call, Home visit,
        # …); everything else keeps the generic import type. Curriculum/session subjects still
        # become trackings below on top of the note.
        ptype = c && c[:kind] == :contact ? note_type_for(c[:note_type]) : default_type
        # response/additional_note are NON-DETERMINISTICALLY encrypted — a WHERE on them can never
        # match, so dedupe compares decrypted values in Ruby within the (client, author, date)
        # candidate set (type-independent so a reclassified note isn't re-imported).
        candidates = ProgressNote.where(client_id: client.id, user_id: author.id, date: date)
        next if candidates.any? { |pn| pn.additional_note == subject && pn.response == narrative }
        ProgressNote.create!(client_id: client.id, user_id: author.id, date: date,
                             progress_note_type_id: ptype.id, location_id: location.id,
                             additional_note: subject, response: narrative)
        @counts['progress notes created'] += 1
        if c && c[:kind] == :bare_session
          bare << { client: client, date: date, week: c[:week] }
        else
          track_classified(client, row, date, enrollments)
        end
      end
      resolve_bare_sessions!(bare)
    end

    # Bare "Week N" subjects name no curriculum — after every explicit session
    # note has implied its cohort enrollment, attribute each bare week to the
    # client's SOLE curriculum enrollment; ambiguous ones stay ProgressNote-only.
    def resolve_bare_sessions!(bare)
      curricula = SubjectClassifier::CURRICULA.values.uniq
      bare.each do |b|
        ces = b[:client].client_enrollments.joins(:program_stream)
                        .where(program_streams: { name: curricula })
        next unless ces.count == 1
        ce = ces.first
        tr = ce.program_stream.trackings.find_by(name: 'Session Attendance') or next
        cet = ClientEnrollmentTracking.where(client_enrollment_id: ce.id, tracking_id: tr.id,
                                             entry_date: b[:date]).first_or_initialize
        next unless cet.new_record?
        cet.properties = { 'Session Number' => b[:week].to_s, 'Attendance' => 'Present' }
        cet.save!
        @counts['tracking entries created'] += 1
      end
    end

    def track_classified(client, row, date, enrollments)
      person = row['Person Name'].to_s.strip
      c = SubjectClassifier.classify(row['Subject'])
      # :contact subjects set the note TYPE only (handled in upsert_notes!) — never a tracking.
      return if c.nil? || %i[assessment_marker contact].include?(c[:kind])
      # Sessions IMPLY cohort participation (a Joven Noble session note is Joven
      # Noble attendance); contact-type trackings do NOT imply enrollment — a
      # Student's one-off 'Navigation' note must not mint an STH enrollment.
      ce = if c[:kind] == :session
             enroll(client, person, c[:program],
                    site: parse_site(row['Subject']), term: parse_term(row['Subject']))
           else
             # program-level contact tracking — attach to ANY cohort enrollment for this program
             # (the map key now carries a cohort; contact trackings aren't cohort-specific).
             enrollments.find { |(p, prog, _cohort), _ce| p == person && prog == c[:program] }&.last
           end
      return if ce.nil?
      tracking_name = c[:kind] == :session ? 'Session Attendance' : c[:tracking]
      tr = ce.program_stream.trackings.find_by(name: tracking_name) or return
      cet = ClientEnrollmentTracking.where(client_enrollment_id: ce.id, tracking_id: tr.id,
                                           entry_date: date).first_or_initialize
      return unless cet.new_record?
      cet.properties = if c[:kind] == :session
                         { 'Session Number' => c[:week].to_s, 'Attendance' => 'Present',
                           'Session Notes' => c[:lesson].to_s }
                       else
                         {}
                       end
      cet.save!
      @counts['tracking entries created'] += 1
    end

    def upsert_agencies!
      @plan[:providers].each do |row|
        name = row['Provider Name'].to_s.strip
        next if name.empty?
        agency = Agency.where('lower(name) = ?', name.downcase).first || Agency.new(name: name)
        agency.description = "Casebook provider_id #{row['provider_id']}; " \
                             "type #{row['Provider Type']}; status #{row['Provider Status']}"
        @counts[agency.new_record? ? 'agencies created' : 'agencies updated'] += 1
        agency.save!
      end
    end

    def fill_form(client, guid, row)
      cfp = CustomFieldProperty.find_or_initialize_by(
        custom_field_id: @form.id, custom_formable_type: 'Client', custom_formable_id: client.id
      )
      cfp.properties = {
        'Casebook person_id' => guid,
        'Age at export' => row['Age'].to_s,
        'Education (Casebook)' => row['Education'].to_s,
        'Birthplace (Casebook)' => row['Birthplace'].to_s,
        'Employment (Casebook)' => [row['Employer Name'], row['Employment Position']].map(&:to_s).reject(&:empty?).join(' — '),
        'Income (Casebook)' => [row['Income Type'], row['Income Amount'], row['Income Frequency']].map(&:to_s).reject(&:empty?).join(' '),
        'Casebook case meta' => ''
      }.compact
      cfp.save!
    end

    def link_quantitative(client, row)
      QUANTITATIVE_MAP.each do |col, type_name|
        raw = row[col].to_s.strip
        next if raw.empty?
        qt = QuantitativeType.find_by(name: type_name) or next
        raw.split(',').map(&:strip).each do |value|
          qc = qt.quantitative_cases.find_by(value: value)
          next @counts['quantitative values unmatched'] += 1 if qc.nil?
          client.quantitative_cases << qc unless client.quantitative_cases.include?(qc)
        end
      end
    end

    # Parse the delivery Site from a free-text case/cohort name via SITE_ABBREV,
    # longest token first so "santa maria" wins over a stray "maria". Returns a
    # canonical Site name or nil.
    def parse_site(text)
      s = text.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase
      SITE_ABBREV.keys.sort_by { |k| -k.length }.each do |token|
        return SITE_ABBREV[token] if s.match?(/\b#{Regexp.escape(token)}\b/)
      end
      nil
    end

    # Parse a Term ("Spring 25", "(Fall 2025)") into the seeded "Season YY" form.
    def parse_term(text)
      m = text.to_s.match(/\b(fall|spring|summer)\s*'?\s*(\d{2,4})\b/i)
      return nil unless m
      "#{m[1].capitalize} #{m[2].to_i % 100}"
    end

    # School of ATTENDANCE (client 'School' quantitative). Only real school campuses
    # have a 'School' value, so a community/other Site is silently skipped. Then
    # youth:link_schools links the client to the kind='school' agency of that name.
    def set_school_from_site(client, site)
      qt = QuantitativeType.find_by(name: 'School') or return
      qc = qt.quantitative_cases.find_by(value: site) or return
      return if ClientQuantitativeCase.where(client_id: client.id, quantitative_case_id: qc.id).exists?
      client.quantitative_cases << qc
      @counts['school set from site'] += 1
    end

    def assignee_for(person)
      row = @plan[:cases].find { |r| r['Person'].to_s.strip == person && r['Assignee'].to_s.strip.present? }
      (row && @users_by_name[row['Assignee'].to_s.strip]) || @import_user
    end

    def address_line(row)
      [row['Address'], row['City'], row['Zip Code']].map { |v| v.to_s.strip }.reject(&:empty?).join(', ')
    end

    def split_name(name)
      parts = name.to_s.strip.split(/\s+/)
      return [name.to_s.strip, ''] if parts.size < 2
      [parts[0..-2].join(' '), parts[-1]]
    end

    def to_date(value)
      case value
      when Date, Time then value.to_date
      when String then value.blank? ? nil : (Date.parse(value) rescue nil)
      end
    end

    def note_type_for(name)
      @note_types[name] ||= ProgressNoteType.find_or_create_by!(note_type: name)
    end
  end
end
