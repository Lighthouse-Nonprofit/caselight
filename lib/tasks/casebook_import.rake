# frozen_string_literal: true

# Youth-flavor batch Y5 — Casebook migration for One Community Action.
# Full column mapping + runbook: docs/casebook-mapping.md.
#
#   rake casebook:audit  CASEBOOK_DIR=/imports/oca          # read-only, aggregates only
#   rake casebook:import CASEBOOK_DIR=/imports/oca          # DRY RUN (plan + counts, no writes)
#   rake casebook:import CASEBOOK_DIR=... TENANT=oca CONFIRM=1   # persists — PRODUCTION ONLY
#
# The synthetic-only rule is enforced in code: import persists only when CONFIRM=1
# AND RAILS_ENV=production AND an explicit TENANT are ALL present. Audit output is
# aggregate-only — client names/narratives are never printed (staff names and note
# Subjects are operational labels, needed for ACTIVE_STAFF= and classifier growth).
namespace :casebook do
  # Workbooks are detected by header signature, not filename.
  SHEET_SIGNATURES = {
    people:     %w[person_id Age],
    cases:      ['case_id', 'Person Role'],
    notes:      %w[Narrative Subject],
    providers:  %w[provider_id],
    services:   ['Service Type', 'Units'],
    population: %w[case_name person_name]
  }.freeze

  ROLE_PROGRAMS = {
    'Student' => '¡Por Vida!',
    'Victim/Survivor' => 'Stop The Hate',
    'Client' => 'Elevate Youth Prevention'
  }.freeze

  IMPORT_FORM_TITLE = 'Imported from Casebook'

  def casebook_dir!
    dir = ENV['CASEBOOK_DIR']
    abort 'CASEBOOK_DIR= is required (directory holding the six Casebook xlsx exports)' if dir.blank?
    abort "CASEBOOK_DIR #{dir} does not exist" unless Dir.exist?(dir)
    dir
  end

  def detect_workbooks(dir)
    found = {}
    Dir[File.join(dir, '*.xlsx')].sort.each do |path|
      reader = Casebook::WorkbookReader.new(path)
      headers = reader.headers
      kind, _sig = SHEET_SIGNATURES.find { |_k, sig| sig.all? { |h| headers.include?(h) } }
      found[kind] = reader if kind && !found.key?(kind)
    end
    found
  end

  def to_date_or_nil(value)
    case value
    when Date, Time then value.to_date
    when String then value.blank? ? nil : (Date.parse(value) rescue nil)
    end
  end

  def split_person_name(name)
    # "Given [Middle] Family" — last token is the family name; the audit surfaces
    # single-token and comma-form names for manual review.
    parts = name.to_s.strip.split(/\s+/)
    return [name.to_s.strip, ''] if parts.size < 2
    [parts[0..-2].join(' '), parts[-1]]
  end

  def blank_rates(rows, headers)
    headers.to_h do |h|
      blank = rows.count { |r| r[h].to_s.strip.empty? }
      [h, rows.empty? ? 0 : (100.0 * blank / rows.size).round(1)]
    end
  end

  # ---- the shared read/plan phase (no writes, no tenant needed) --------------
  def build_plan(dir)
    books = detect_workbooks(dir)
    missing = SHEET_SIGNATURES.keys - books.keys
    people = books[:people]&.rows || []
    cases = books[:cases]&.rows || []
    notes = books[:notes]&.rows || []
    providers = books[:providers]&.rows || []

    by_name = people.group_by { |r| r['Person Name'].to_s.strip }.reject { |n, _| n.empty? }
    collided = by_name.select { |_n, rs| rs.size > 1 }
    # OCA 2026-08 (graceful collisions): import ALL named people as distinct clients (the applier keys
    # on person_id). A collided NAME maps to the FIRST person for name-keyed cases/notes (best-effort;
    # the audit still lists collisions for a manual split); collided_extra holds the 2nd+ so those
    # people are still created as clients rather than silently dropped.
    resolvable = by_name.transform_values(&:first)
    collided_extra = collided.flat_map { |_n, rs| rs.drop(1) }

    notes_by_person = notes.group_by { |r| r['Person Name'].to_s.strip }
    note_dates = notes_by_person.transform_values do |rs|
      rs.filter_map { |r| to_date_or_nil(r['Contact Start Date']) }.minmax
    end

    classified = notes.map { |r| [r, Casebook::SubjectClassifier.classify(r['Subject'])] }
    staff = (cases.map { |r| r['Assignee'].to_s.strip } + notes.map { |r| r['Author'].to_s.strip })
            .reject(&:empty?).tally

    enrollments = []
    exits = []
    families = {}
    unresolved_case_rows = 0
    cases.each do |row|
      person = row['Person'].to_s.strip
      next unresolved_case_rows += 1 unless resolvable.key?(person)
      role = row['Person Role'].to_s.strip
      program = nil # reset per row — a bare local leaks across each-iterations otherwise
      if role == 'Parent'
        (families[row['case_id']] ||= { case_name: row['Case Name'], members: [] })[:members] << person
        # OCA 2026-08: parents are their OWN participants (Cara y Corazón adult cohort), not just
        # household members — enroll them too, keeping the family link above.
        program = 'Cara y Corazón'
      end
      program ||= ROLE_PROGRAMS[role]
      if program
        enrollments << { person: person, program: program, row: row }
        status = row['Case Status'].to_s.strip
        exits << { person: person, program: program, exit_date: note_dates.dig(person, 1) } unless status == 'Active'
      end
    end
    # a family needs its youths too — pull every resolvable person on a parented case
    cases.each do |row|
      fam = families[row['case_id']]
      person = row['Person'].to_s.strip
      fam[:members] << person if fam && resolvable.key?(person) && !fam[:members].include?(person)
    end

    session_entries = classified.filter_map do |row, c|
      next unless c
      person = row['Person Name'].to_s.strip
      next unless resolvable.key?(person)
      { person: person, note: row, classification: c }
    end

    {
      books: books, missing: missing, people: people, cases: cases, notes: notes,
      providers: providers, collided: collided, collided_extra: collided_extra, resolvable: resolvable,
      notes_by_person: notes_by_person, note_dates: note_dates, classified: classified,
      staff: staff, enrollments: enrollments, exits: exits, families: families,
      unresolved_case_rows: unresolved_case_rows, session_entries: session_entries
    }
  end

  desc 'Read-only audit of a Casebook export directory. Aggregates only — no PII printed.'
  task audit: :environment do
    plan = build_plan(casebook_dir!)
    puts "== Casebook audit (#{ENV['CASEBOOK_DIR']}) =="
    puts "workbooks missing: #{plan[:missing].join(', ')}" if plan[:missing].any?

    { people: 'People Data Table', cases: 'Cases Data Table', notes: 'Client Notes',
      providers: 'Providers Data Table' }.each do |kind, label|
      reader = plan[:books][kind]
      next puts("#{label}: MISSING") if reader.nil?
      rows = plan[kind]
      puts "\n#{label}: #{rows.size} rows — blank rates (%):"
      blank_rates(rows, reader.headers).sort_by { |_h, pct| -pct }.each do |h, pct|
        puts format('  %5.1f  %s', pct, h)
      end
    end

    puts "\nName join: #{plan[:collided].size} collided name(s) covering " \
         "#{plan[:collided].values.sum(&:size)} People rows; " \
         "#{plan[:unresolved_case_rows]} case rows skip (no unique People match)."

    total = plan[:classified].size
    hits = plan[:classified].count { |_r, c| c }
    puts "\nSubject classifier: #{hits}/#{total} classified " \
         "(#{total.zero? ? 0 : (100.0 * hits / total).round(1)}%). Top unclassified subjects:"
    plan[:classified].reject { |_r, c| c }.map { |r, _c| r['Subject'].to_s.strip }
        .reject(&:empty?).tally.sort_by { |_s, n| -n }.first(20)
        .each { |s, n| puts format('  %5d  %s', n, s) }

    puts "\nStaff seen (Assignee/Author) — pass the still-active ones as ACTIVE_STAFF= on import:"
    plan[:staff].sort_by { |_n, c| -c }.each { |n, c| puts format('  %5d  %s', c, n) }

    puts "\nWould import: #{plan[:resolvable].size} clients, #{plan[:enrollments].size} enrollments " \
         "(#{plan[:exits].size} exited), #{plan[:families].size} families, " \
         "#{plan[:notes].size} progress notes (+#{plan[:session_entries].size} tracking entries), " \
         "#{plan[:providers].size} agencies."
  end

  desc 'Import Casebook data. DRY RUN unless CONFIRM=1 + RAILS_ENV=production + TENANT=.'
  task import: :environment do
    plan = build_plan(casebook_dir!)
    puts "PLAN: #{plan[:resolvable].size} clients / #{plan[:enrollments].size} enrollments " \
         "(#{plan[:exits].size} exits) / #{plan[:families].size} families / " \
         "#{plan[:notes].size} notes (+#{plan[:session_entries].size} tracking entries) / " \
         "#{plan[:providers].size} agencies / #{plan[:staff].size} staff accounts"

    gates = { 'CONFIRM=1' => ENV['CONFIRM'] == '1',
              'RAILS_ENV=production' => Rails.env.production?,
              'TENANT=' => ENV['TENANT'].present? }
    unless gates.values.all?
      puts "DRY RUN — no writes. Missing gate(s): #{gates.reject { |_k, v| v }.keys.join(', ')}"
      puts '(Real client data belongs on the production youth box ONLY — SECURITY.md.)'
      next
    end

    active_staff = ENV['ACTIVE_STAFF'].to_s.split(',').map(&:strip).reject(&:empty?)
    Apartment::Tenant.switch(ENV['TENANT']) do
      Casebook::Applier.new(plan, active_staff: active_staff).apply!
    end
    puts 'Import complete.'
  end
end
