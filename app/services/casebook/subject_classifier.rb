# frozen_string_literal: true

module Casebook
  # Maps a Casebook Client-Note "Subject" onto the youth-flavor taxonomy (Y3).
  # The Subject column is OCA's de-facto service log — "Week 2 Joven Noble:
  # Palabra" is a cohort session, "1:1 check-in" a mentorship contact — so the
  # importer turns classified notes into tracking entries (entry_date = the
  # note's contact date) on top of the ProgressNote every note becomes.
  #
  # Returns nil (ProgressNote only) or a hash:
  #   {kind: :session, program: <curriculum>, week: 2, lesson: 'Palabra'}
  #   {kind: :tracking, program: '¡Por Vida!', tracking: 'Mentorship Contact'}
  #   {kind: :assessment_marker, phase: 'Pre'}   # audit-listed, never auto-created
  class SubjectClassifier
    # Casebook subjects often drop diacritics/articles; keys are normalized
    # (lowercase, no diacritics) token → the seeded ProgramStream name.
    CURRICULA = {
      'joven noble' => 'El Joven Noble',
      'el joven noble' => 'El Joven Noble',
      'girasol' => 'Girasol',
      'cara y corazon' => 'Cara y Corazón',
      'nurturing our futures' => 'Nurturing Our Futures',
      'nurturing' => 'Nurturing Our Futures',
      'susto y limpia' => 'Susto y Limpia',
      'susto' => 'Susto y Limpia',
      'mi palabra' => 'Mi Palabra',
      # OCA 2026-08 (owner decision): the three biggest unclassified curriculum buckets become
      # their own programs. Seeded by youth:seed_casebook_programs.
      'cultura club' => 'Cultura Club',
      'celebracion' => 'Celebración',
      'ancestral teachings' => 'Ancestral Teachings',
      'ancestral teaching' => 'Ancestral Teachings'
    }.freeze

    # OCA's session notes come in several shapes: "Week 8- Tsa Ho Fa", "Session 10: Warrior",
    # "Clase 7-Objectivo". Capture N and the rest; a leading curriculum token (if any) is matched
    # separately below, so a bare "Session 3" resolves against the person's sole cohort enrollment.
    WEEK_SESSION = /\Aweek\s+(\d+)\s+([^:]+?)\s*(?::\s*(.+))?\z/i
    BARE_SESSION = /\A(?:week|session|clase|semana)\s*[#\-]?\s*(\d+)\b[\-:\s]*(.*)\z/i

    # Contact-type subjects — a note ABOUT a contact, not a curriculum session. These set the
    # ProgressNote's TYPE (owner ask: "make sure we have all the note types") and never mint an
    # enrollment. Order matters: most specific first. Values are seeded ProgressNoteType names
    # (youth:seed_casebook_note_types). Matched on the normalized subject.
    CONTACT_TYPES = [
      [/parent (phone|call|meeting|contact)/,            'Parent contact'],
      [/phone call|phone called|called|phone contact/,   'Phone call'],
      [/home visit/,                                     'Home visit'],
      [/drop.?in/,                                        'Drop-in'],
      [/e.?mail/,                                         'Email'],
      [/attempt(ed)? to (meet|contact)|no answer|no response|unable to reach/, 'Attempted contact'],
      [/ride provided|transportation|drove/,             'Transportation'],
      [/(wellness )?check.?in|welcome back/,             'Check-in'],
      [/intake|needs assessment|success plan|smart goal/, 'Intake / assessment'],
      [/referral|referred to/,                            'Referral'],
      [/closing (note|case)|last (check|session)|reintroduction|welcome/, 'Closing / status'],
      [/individual meeting|1[:\-\s]?1|one.on.one|meeting w|meet(ing)? with (student|counselor|staff)/, 'Individual meeting'],
      [/clothing|food (resource|assistance|bank)|resource/, 'Resource / navigation']
    ].freeze

    def self.classify(subject)
      s = subject.to_s.strip
      return nil if s.empty?

      if (m = s.match(WEEK_SESSION))
        program = CURRICULA[normalize(m[2])]
        return { kind: :session, program: program, week: m[1].to_i, lesson: m[3] } if program
      end

      # OCA's real subjects mostly carry the curriculum WITHOUT a Week prefix:
      # "Joven Noble Group", "Joven Noble 6: El Otro Yo", "Girasol Intro". Match
      # the curriculum token anywhere — but only when exactly ONE matches.
      norm = normalize(s)
      hits = CURRICULA.filter_map { |token, program| program if norm.include?(token) }.uniq
      if hits.size == 1
        # "Joven Noble 6: El Otro Yo" → session 6; "Joven Noble 2/11/25" is a
        # DATE, not a session number — only digits directly before a colon (or
        # a "Week N" fragment) count.
        week = s[/week\s+(\d+)/i, 1] || s[/\b(\d{1,2})\s*:/, 1]
        return { kind: :session, program: hits.first, week: week&.to_i,
                 lesson: s[/:\s*(.+)\z/, 1] }
      end

      # Bare "Week/Session/Clase N" can't name its curriculum — the applier resolves it against
      # the person's sole cohort enrollment (or drops it if ambiguous).
      if (m = s.match(BARE_SESSION))
        out = { kind: :bare_session, week: m[1].to_i }
        out[:lesson] = m[2].strip if m[2].present?
        return out
      end

      # Existing program-tracking rules run BEFORE the generic contact types, so "1:1 check-in"
      # stays a mentorship tracking rather than a bare contact note.
      program_tracking =
        case norm
        when /\A1[:\-]1 check.?in/, /\Acheck.?in\z/
          { kind: :tracking, program: '¡Por Vida!', tracking: 'Mentorship Contact' }
        when /\Acase (management|mgmt)\b/
          { kind: :tracking, program: '¡Por Vida!', tracking: 'Case Management Contact' }
        when /\Anavigation\b/, /food (resource|assistance)/, /referral for food/
          { kind: :tracking, program: 'Stop The Hate', tracking: 'Navigation / Case Mgmt / Referral' }
        when /(pre|post).?\s*assessment/
          { kind: :assessment_marker, phase: Regexp.last_match(1).capitalize }
        end
      return program_tracking if program_tracking

      # Contact-type subjects → the ProgressNote's TYPE (no enrollment/tracking).
      CONTACT_TYPES.each { |re, type| return { kind: :contact, note_type: type } if norm.match?(re) }
      nil
    end

    def self.normalize(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.strip
    end
  end
end
