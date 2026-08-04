# frozen_string_literal: true

module Reports
  # Base class for every registry report. Contract:
  #   * @clients arrives ALREADY ability-scoped (Client.accessible_by upstream) —
  #     the one scope gate; subclasses never widen it.
  #   * masking inputs default FAIL-CLOSED (standard-only domains, no custom forms),
  #     the CsiStatistic precedent — a caller that forgets to pass them over-masks.
  #   * output is per-viewer; NOTHING may be cached across requests (per-instance
  #     memoization only).
  #   * zero counts render as rows — funders require reported zeros, and an empty
  #     cohort must be visible as such.
  class BaseReport
    # columns: array of i18n-resolved header strings; rows: array of arrays;
    # restricted_hidden: the section exists but the viewer's sensitivity clearance
    # hides it (render the notice, never fabricate zeros);
    # chart: optional { type: :line|:pie, data: <CIF.ReportCreator payload> }.
    # `title` is for DYNAMIC sections whose key can't live in en.yml (one per
    # quantitative type / cohort program) — without it, CSV and PDF exports fall
    # back to humanize and a funder reads "Quant english proficiency".
    Section = Struct.new(:key, :columns, :rows, :footnote, :restricted_hidden, :chart,
                         :title, keyword_init: true) do
      def restricted_hidden? = !!restricted_hidden
    end

    attr_reader :definition, :period

    def initialize(definition:, clients:, period:,
                   visible_domain_levels: [SensitivityPolicy::STANDARD],
                   visible_custom_field_ids: Set.new, viewer: nil)
      @definition = definition
      @clients = clients
      @period = period
      @visible_domain_levels = Array(visible_domain_levels)
      @visible_custom_field_ids = visible_custom_field_ids || Set.new
      @viewer = viewer
    end

    def sections
      @sections ||= build_sections
    end

    def title = definition.title
    def description = definition.description

    def filename_stem
      "#{definition.slug}_#{period.start_date.iso8601}_#{period.end_date.iso8601}"
    end

    # Stdlib CSV: per section — section title row, header row, data rows, blank line.
    # Restricted-hidden sections emit the notice line only (no values in any format).
    def to_csv
      CSV.generate do |csv|
        csv << [title, period.label]
        csv << []
        sections.each do |section|
          csv << [section_title(section)]
          if section.restricted_hidden?
            csv << [I18n.t('reports.show.restricted_hidden')]
          else
            csv << section.columns
            section.rows.each { |row| csv << row }
            csv << [I18n.t('reports.show.no_data')] if section.rows.empty?
          end
          csv << []
        end
      end
    end

    def section_title(section)
      return section.title if section.title.present?
      I18n.t("reports.registry.#{definition.i18n_key}.sections.#{section.key}",
             default: section.key.to_s.humanize)
    end

    private

    attr_reader :visible_domain_levels, :visible_custom_field_ids, :viewer

    def build_sections
      raise NotImplementedError
    end

    def client_ids
      @client_ids ||= @clients.ids
    end

    def scoped_enrollments(program_ids = nil)
      rel = ClientEnrollment.where(client_id: client_ids)
      rel = rel.where(program_stream_id: program_ids) if program_ids
      rel
    end

    def scoped_trackings(range = period.range)
      ClientEnrollmentTracking
        .joins(:client_enrollment)
        .where(entry_date: range, client_enrollments: { client_id: client_ids })
    end

    # Unduplicated household count for a set of client ids: distinct families via
    # the KC (household) case; clients without any KC case count as single-person
    # households (else they'd vanish from household totals).
    def household_count(ids)
      ids = Array(ids)
      return 0 if ids.empty?
      # A KC case with a NULL family_id counts for nothing in count(:family_id),
      # and its client would ALSO be excluded from the singles remainder — so
      # only clients whose KC case actually names a family are "in a household".
      in_households = Case.where(client_id: ids, case_type: 'KC').where.not(family_id: nil)
      in_households.distinct.count(:family_id) +
        (ids - in_households.distinct.pluck(:client_id)).size
    end

    # Roster policy (plan default D12): strategic overviewer reads leadership
    # AGGREGATES but per-person rosters render as anonymous ids — the
    # leadership-read-only role stays values-lean in exports.
    def roster_names_allowed?
      viewer.nil? || !viewer.strategic_overviewer?
    end

    def client_label(client)
      roster_names_allowed? ? client.name : "##{client.id}"
    end

    AGE_BANDS = ['0-4', '5-17', '18-24', '25-44', '45-59', '60+'].freeze

    def age_band(dob, as_of = period.end_date)
      return I18n.t('reports.show.unknown') if dob.blank?
      age = as_of.year - dob.year - ((as_of.month > dob.month ||
            (as_of.month == dob.month && as_of.day >= dob.day)) ? 0 : 1)
      case age
      when 0..4 then '0-4'
      when 5..17 then '5-17'
      when 18..24 then '18-24'
      when 25..44 then '25-44'
      when 45..59 then '45-59'
      else '60+'
      end
    end

    # SERVED definition (plan default): enrolled-in-period ∪ service-contact-in-period.
    # Returns distinct client ids within the report's ability scope.
    def served_client_ids(program_ids = nil)
      enrolled = scoped_enrollments(program_ids)
                 .where(enrollment_date: period.range).pluck(:client_id)
      contacts = scoped_trackings
      contacts = contacts.where(client_enrollments: { program_stream_id: program_ids }) if program_ids
      (enrolled + contacts.pluck('client_enrollments.client_id')).uniq
    end
  end
end
