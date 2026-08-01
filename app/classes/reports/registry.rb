# frozen_string_literal: true

module Reports
  # The per-flavor report registry — the FLAVOR_SEEDS pattern applied to reporting.
  # Each Definition: slug (URL id), klass_name (a Reports::* BaseReport subclass),
  # audience (MINIMUM tier — higher tiers always see lower-tier reports), presets
  # (Reports::Period allowlist for the picker).
  #
  # Tier model (owner decision, reports batch): worker = outcomes/progress of THEIR
  # cases; manager = org/team-wide case operations; leadership = everything incl.
  # funder-facing sets. Tier controls WHICH definitions a role may run; every report
  # additionally scopes its data through Client.accessible_by(current_ability), so a
  # mis-tiered report still cannot leak records outside the viewer's ability.
  class Registry
    TIER_ACTIONS = { worker: :report_worker, manager: :report_manager,
                     leadership: :report_leadership }.freeze
    TIER_ORDER = %i[worker manager leadership].freeze

    Definition = Struct.new(:slug, :klass_name, :audience, :presets, keyword_init: true) do
      def klass = klass_name.constantize
      def i18n_key = slug.tr('-', '_')
      def title = I18n.t("reports.registry.#{i18n_key}.title")
      def description = I18n.t("reports.registry.#{i18n_key}.description")

      def build(**kwargs) = klass.new(definition: self, **kwargs)
    end

    # Entries are added rung-by-rung as their classes land; the spec proves every
    # registered klass resolves and carries base i18n.
    REGISTRY = {
      'resettlement' => [
        Definition.new(slug: 'served-summary', klass_name: 'Reports::Resettlement::ServedSummary',
                       audience: :leadership,
                       presets: %i[ffy orr_trimester ca_sfy calendar_year custom])
      ],
      'youth' => [
        Definition.new(slug: 'youth-served', klass_name: 'Reports::Youth::YouthServed',
                       audience: :leadership,
                       presets: %i[sfy_quarter term eyc_half calendar_year custom])
      ]
    }.freeze

    def self.for_flavor(flavor = Rails.application.config.x.flavor)
      REGISTRY.fetch(flavor)
    end

    def self.visible_to(ability, flavor: Rails.application.config.x.flavor)
      for_flavor(flavor).select { |d| ability.can?(TIER_ACTIONS.fetch(d.audience), :report) }
    end

    # Searches ONLY the active flavor's list — a youth slug on a resettlement box
    # 404s, matching the boot-time flavor whitelist posture.
    def self.find!(slug, flavor: Rails.application.config.x.flavor)
      for_flavor(flavor).find { |d| d.slug == slug } or
        raise ActiveRecord::RecordNotFound, "unknown report #{slug.inspect} for flavor #{flavor}"
    end
  end
end
