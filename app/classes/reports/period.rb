# frozen_string_literal: true

module Reports
  # The reporting-period resolver. Pure date math (Time.zone-aware, travel_to-testable):
  # every funder calendar the two flavors answer to, resolved to a Date range.
  #
  #   ffy           Federal fiscal year Oct 1 – Sep 30 (ORR and federal pass-throughs)
  #   orr_trimester T1 Oct–Jan, T2 Feb–May, T3 Jun–Sep (ORR-6 / CDSS RS-50/51 cadence)
  #   ca_sfy        California state fiscal year Jul 1 – Jun 30
  #   sfy_quarter   SFY quarters: Q1 Jul–Sep, Q2 Oct–Dec, Q3 Jan–Mar, Q4 Apr–Jun
  #                 (CDSS Stop the Hate quarterly cadence)
  #   term          School terms: Fall = Aug 1 – Dec 31, Spring = Jan 1 – Jun 30.
  #                 Carries term_label ("Fall 25") matching the cohort enrollment
  #                 Term field values for sidecar equality probes.
  #   eyc_half      Elevate Youth CA halves: Jan–Jun / Jul–Dec
  #   calendar_year Jan 1 – Dec 31
  #   custom        Arbitrary from/to (grant periods)
  #
  # An option value round-trips as "preset|start_iso|end_iso" — resolve validates
  # the preset against the definition's allowlist and re-derives everything else,
  # so a tampered range can widen a WINDOW but never the viewer's data scope
  # (every report queries through Client.accessible_by upstream).
  class Period
    PRESETS = %i[ffy orr_trimester ca_sfy sfy_quarter term eyc_half calendar_year custom].freeze
    HISTORY_PER_PRESET = 3

    attr_reader :preset, :range

    def initialize(preset:, range:)
      @preset = preset.to_sym
      @range = range
      raise ArgumentError, "unknown preset #{preset}" unless PRESETS.include?(@preset)
      raise ArgumentError, 'empty period' if range.begin > range.end
    end

    def start_date = range.begin
    def end_date = range.end

    # "Fall 25" / "Spring 26" — matches the youth taxonomy's Term select values.
    def term_label
      return nil unless preset == :term
      if start_date.month >= 8
        "Fall #{start_date.strftime('%y')}"
      else
        "Spring #{start_date.strftime('%y')}"
      end
    end

    def label
      case preset
      when :ffy           then I18n.t('reports.periods.ffy', label: fiscal_year_ending(9))
      when :orr_trimester then I18n.t('reports.periods.orr_trimester', label: trimester_label)
      when :ca_sfy        then I18n.t('reports.periods.ca_sfy', label: fiscal_year_ending(6))
      when :sfy_quarter   then I18n.t('reports.periods.sfy_quarter', label: sfy_quarter_label)
      when :term          then I18n.t('reports.periods.term', label: term_label)
      when :eyc_half      then I18n.t('reports.periods.eyc_half', label: eyc_half_label)
      when :calendar_year then I18n.t('reports.periods.calendar_year', label: start_date.year)
      when :custom        then I18n.t('reports.periods.custom_label', from: start_date.iso8601, to: end_date.iso8601)
      end
    end

    def param_value = "#{preset}|#{start_date.iso8601}|#{end_date.iso8601}"

    class << self
      # Resolve from request params against a registry definition. Falls back to
      # the CURRENT instance of the definition's first preset.
      def resolve(definition, params)
        if params[:period].present?
          preset, from, to = params[:period].to_s.split('|')
          preset = preset.to_s.to_sym
          # from/to may be missing (truncated or hand-edited URL) — Date.iso8601(nil)
          # raises TypeError, which the rescue below does NOT catch, so guard here.
          if definition.presets.include?(preset) && preset != :custom && from.present? && to.present?
            return new(preset: preset, range: Date.iso8601(from)..Date.iso8601(to))
          end
        end
        if definition.presets.include?(:custom) && params[:from].present? && params[:to].present?
          from = Date.iso8601(params[:from].to_s)
          to = Date.iso8601(params[:to].to_s)
          return new(preset: :custom, range: from..to) if from <= to
        end
        current(definition.presets.first)
      rescue ArgumentError, Date::Error
        current(definition.presets.first)
      end

      # The instance containing today — or, for gapped calendars (July sits in no
      # school term), the most recently completed instance. :custom → trailing 30 days.
      def current(preset)
        today = Time.zone.today
        return new(preset: :custom, range: (today - 30)..today) if preset == :custom
        ranges = instances_of(preset)
        range = ranges.find { |r| r.cover?(today) } ||
                ranges.select { |r| r.end < today }.max_by(&:end)
        new(preset: preset, range: range)
      end

      # Recent instances (newest first) for the show-page picker.
      def options_for(definition)
        definition.presets.flat_map do |preset|
          next [] if preset == :custom
          instances_of(preset).sort_by(&:begin).reverse.first(HISTORY_PER_PRESET).map do |r|
            new(preset: preset, range: r)
          end
        end
      end

      private

      # Concrete ranges around today, newest-capable first pass: generate for the
      # window [today - 2 years, today] plus the current instance.
      def instances_of(preset)
        today = Time.zone.today
        case preset
        when :ffy
          (0..2).map { |i| y = ffy_ending_year(today) - i; Date.new(y - 1, 10, 1)..Date.new(y, 9, 30) }
        when :orr_trimester
          ffy_starts = (0..2).map { |i| Date.new(ffy_ending_year(today) - 1 - i, 10, 1) }
          ffy_starts.flat_map do |s|
            [s..(s >> 4) - 1, (s >> 4)..(s >> 8) - 1, (s >> 8)..(s >> 12) - 1]
          end
        when :ca_sfy
          (0..2).map { |i| y = sfy_ending_year(today) - i; Date.new(y - 1, 7, 1)..Date.new(y, 6, 30) }
        when :sfy_quarter
          starts = (0..8).map { |i| Date.new(today.year, today.month, 1) << (3 * i) }
                         .map { |d| Date.new(d.year, ((d.month - 1) / 3) * 3 + 1, 1) }.uniq
          starts.map { |s| s..(s >> 3) - 1 }
        when :term
          (0..2).flat_map do |i|
            y = today.year - i
            [Date.new(y, 1, 1)..Date.new(y, 6, 30), Date.new(y, 8, 1)..Date.new(y, 12, 31)]
          end
        when :eyc_half
          (0..1).flat_map do |i|
            y = today.year - i
            [Date.new(y, 1, 1)..Date.new(y, 6, 30), Date.new(y, 7, 1)..Date.new(y, 12, 31)]
          end
        when :calendar_year
          (0..2).map { |i| y = today.year - i; Date.new(y, 1, 1)..Date.new(y, 12, 31) }
        else
          []
        end
      end

      def ffy_ending_year(today) = today.month >= 10 ? today.year + 1 : today.year
      def sfy_ending_year(today) = today.month >= 7 ? today.year + 1 : today.year
    end

    private

    def fiscal_year_ending(_end_month) = end_date.year

    def trimester_label
      n = { 10 => 1, 2 => 2, 6 => 3 }[start_date.month]
      "T#{n} FFY#{preset == :orr_trimester ? (start_date.month >= 10 ? start_date.year + 1 : start_date.year) : end_date.year}"
    end

    def sfy_quarter_label
      n = { 7 => 1, 10 => 2, 1 => 3, 4 => 4 }[start_date.month]
      sfy = start_date.month >= 7 ? start_date.year + 1 : start_date.year
      "Q#{n} SFY#{sfy}"
    end

    def eyc_half_label
      half = start_date.month == 1 ? 'Jan–Jun' : 'Jul–Dec'
      "#{half} #{start_date.year}"
    end
  end
end
