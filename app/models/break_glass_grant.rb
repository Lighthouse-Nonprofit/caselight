class BreakGlassGrant < ActiveRecord::Base
  # Phase 5.4 — see db/migrate/20260626000003_create_break_glass_grants.rb for the NIST
  # AC-3 / AC-6 / AU-2 framing. One row == one user's 1-hour emergency elevation on one record
  # (and optionally one emergency_only form on it).
  #
  # PLAIN AR record in the TENANT schema (NOT in Apartment.excluded_models) so every tenant gets
  # its own table and a grant can NEVER leak across orgs. NO has_paper_trail: the grant is the
  # access-control fact; the AUDIT is the AccessLog "break_glass" row (Mongo), written by the
  # controller BEFORE this row is created.

  belongs_to :user, optional: false

  CUSTOM_FORMABLE_TYPES = %w[Client Family Partner].freeze
  GRANT_WINDOW = 1.hour

  validates :user_id, :custom_formable_type, :custom_formable_id, :expires_at, presence: true
  validates :custom_formable_type, inclusion: { in: CUSTOM_FORMABLE_TYPES }
  validates :reason, presence: true

  scope :active, -> { where('expires_at > ?', Time.current) }

  scope :for_user_and_record, lambda { |user, record|
    where(
      user_id:              user.try(:id),
      custom_formable_type: record.class.base_class.name,
      custom_formable_id:   record.id
    )
  }

  # Does an active grant exist for (user, record)? FAIL-CLOSED: a missing table (tenant not yet
  # apartment:migrated — bypass D) raises StatementInvalid; rescue to FALSE so emergency_only
  # stays denied rather than 500.
  def self.active_for?(user, record)
    return false if user.nil? || record.nil?
    for_user_and_record(user, record).active.exists?
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error("[BreakGlassGrant] active_for? failed (fail-closed): #{e.class}: #{e.message}")
    false
  end

  # The emergency_only custom_field_ids unlocked for (user, record) now. Returns:
  #   * an Array of concrete Integer ids for form-scoped grants;
  #   * [:all] sentinel when ANY active grant is record-wide (custom_field_id NULL) — the
  #     READ-PATH caller (SensitiveFields#break_glass_form_ids_for) resolves :all to the concrete
  #     emergency_only ids on the record before the policy sees it (the policy rejects :all);
  #   * [] (deny) when no active grant OR the table is missing (fail-closed).
  def self.active_form_ids_for(user, record)
    return [] if user.nil? || record.nil?
    grants = for_user_and_record(user, record).active
    return [:all] if grants.where(custom_field_id: nil).exists?
    grants.where.not(custom_field_id: nil).distinct.pluck(:custom_field_id)
  rescue ActiveRecord::StatementInvalid => e
    Rails.logger.error("[BreakGlassGrant] active_form_ids_for failed (fail-closed): #{e.class}: #{e.message}")
    []
  end
end
