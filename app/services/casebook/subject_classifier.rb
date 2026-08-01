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
      'mi palabra' => 'Mi Palabra'
    }.freeze

    WEEK_SESSION = /\Aweek\s+(\d+)\s+([^:]+?)\s*(?::\s*(.+))?\z/i
    BARE_WEEK    = /\Aweek\s+(\d+)\z/i

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

      # Bare "Week N" can't name its curriculum — the applier resolves it against
      # the person's sole cohort enrollment (or drops it if ambiguous).
      if (m = s.match(BARE_WEEK))
        return { kind: :bare_session, week: m[1].to_i }
      end

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
    end

    def self.normalize(str)
      str.to_s.unicode_normalize(:nfkd).gsub(/\p{Mn}/, '').downcase.strip
    end
  end
end
