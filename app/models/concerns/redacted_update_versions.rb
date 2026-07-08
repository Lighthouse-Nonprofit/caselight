# frozen_string_literal: true

# RedactedUpdateVersions — Phase 6 (SC-28 / POAM-SC28-HIST companion).
#
# paper_trail's `skip:` option implies ignore-for-version-creation: a save that changes ONLY
# skipped attributes is not "notable" (events/base.rb changed_notably?), so NO version row is
# written at all. With the Phase-6 skip lists that would silently drop the who/when change-audit
# trail for exactly the edits being redacted — e.g. every custom-form save (CustomFieldProperty's
# only mutable content is the skipped `properties`), or a client name/address correction.
#
# This concern restores the AU-3 who/when contract: when a save changed only skipped attributes,
# force-record an update version. The forced version is built through the same event pipeline, so
# `object` / `object_changes` still have the skip list applied — it carries whodunnit / event /
# item / created_at and NO PII values. When any non-skipped attribute changed, paper_trail already
# recorded normally and this callback stays out of the way.
#
# Include AFTER `has_paper_trail` (needs paper_trail_options). Never raises into the save.
module RedactedUpdateVersions
  extend ActiveSupport::Concern

  included do
    after_update :record_redacted_update_version
  end

  private

  def record_redacted_update_version
    skip = self.class.paper_trail_options[:skip].map(&:to_s)
    return if skip.empty?

    changed = saved_changes.keys - %w[updated_at created_at]
    return if changed.empty?               # touch-only / timestamp-only save
    return unless (changed - skip).empty?  # a non-skipped attr changed => already recorded normally

    # record_update self-guards on PaperTrail enablement (request + model), so a versioning-disabled
    # context (or PaperTrail.request.disable_model) stays a no-op.
    paper_trail.record_update(force: true, in_after_callback: true, is_touch: false)
  rescue StandardError => e
    Rails.logger.error("[RedactedUpdateVersions] #{self.class.name}##{id}: #{e.class}: #{e.message}")
  end
end
