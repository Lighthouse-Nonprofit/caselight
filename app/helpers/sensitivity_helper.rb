# frozen_string_literal: true

# SensitivityHelper — Phase 5.3 (NIST AC-6) VIEW-facing seam for ASSESSMENT/Domain masking. Views do
# NO role logic; they ask this helper, which delegates to SensitivityPolicy#visible_domain_levels.
# Keyed on domains.sensitivity. emergency_only domains stay masked for every non-admin.
module SensitivityHelper
  # Array<String> of Domain sensitivity levels the current viewer may see. Prefer a controller-set
  # ivar (reuse the same set server-side); else compute from current_user. Recompute when blank
  # (nil OR []) so an empty assignment cannot over-mask via `||=` truthiness.
  def visible_domain_levels
    if !instance_variable_defined?(:@visible_domain_levels) || @visible_domain_levels.blank?
      @visible_domain_levels =
        begin
          SensitivityPolicy.new(current_user).visible_domain_levels
        rescue => e
          Rails.logger.error("[SensitivityHelper] visible_domain_levels failed (failing closed): #{e.class}: #{e.message}")
          [SensitivityPolicy::STANDARD]
        end
    end
    @visible_domain_levels
  end

  # True iff the viewer may see VALUES on a Domain / AssessmentDomain with this sensitivity. Accepts a
  # Domain, an AssessmentDomain (resolves ad.domain), or a raw level String. Fail-closed.
  def domain_visible?(domain_or_ad)
    return false if domain_or_ad.nil?
    domain =
      if domain_or_ad.respond_to?(:domain) && !domain_or_ad.respond_to?(:sensitivity)
        domain_or_ad.domain
      else
        domain_or_ad
      end
    return false if domain.nil?
    level = domain.respond_to?(:sensitivity) ? domain.sensitivity : domain.to_s
    visible_domain_levels.include?(level)
  rescue => e
    Rails.logger.error("[SensitivityHelper] domain_visible? failed (failing closed): #{e.class}: #{e.message}")
    false
  end
end
