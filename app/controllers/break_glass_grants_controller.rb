class BreakGlassGrantsController < AdminController
  # Phase 5.4 — DEDICATED break-glass elevation endpoint (NIST AC-3 / AC-6(2) / AU-2).
  #
  # WHY DEDICATED (bypass E): break-glass must NOT be a member action of ClientsController —
  # there it would authorize a nonexistent `can :break_glass, Client` and ClientsController's
  # load_and_authorize_resource would block loading any out-of-caseload record. This controller
  # has its OWN narrow check (`can :create, BreakGlassGrant`) and does the record-readability
  # gate itself via accessible_by.
  #
  # CROSS-CASELOAD RULE (LOCKED): self-elevation ONLY on a record the user can already :read.
  # Enforced by loading through accessible_by(current_ability) — an unreadable record is not found.
  #
  # FAIL-CLOSED DUAL-STORE (bypass D): the grant (Postgres tenant schema) and the audit (Mongo
  # AccessLog) have NO shared transaction. Write the AccessLog "break_glass" row FIRST and create
  # the grant ONLY IF that audit write returned a row. security_event! rescues internally and
  # returns nil on failure, so a Mongo outage aborts the grant. Never an un-audited grant.
  #
  # AUTHORIZE-ONLY (not load_and_authorize_resource): with `class: false` CanCan's LOAD step still
  # BUILDS a resource for #create (build_resource -> resource_class.new), and resource_class is the
  # symbol :break_glass_grant -> `:break_glass_grant.new` => NoMethodError (a 500). We don't want
  # CanCan to load/build anything here (the controller builds the grant itself AFTER the readability
  # gate), so only AUTHORIZE the action against the symbol — matched by `can :create, :break_glass_grant`.
  authorize_resource class: false

  # POST /break_glass_grants
  def create
    record = find_readable_record

    if record.nil?
      log_denied(reason: 'record not readable by current_user (cross-caseload self-elevation denied)')
      return deny('You cannot grant yourself emergency access to a record outside your caseload.')
    end

    if grant_reason.blank?
      log_denied(record: record, reason: 'missing break-glass justification')
      return deny('A reason is required to use emergency access.')
    end

    expires_at = Time.current + BreakGlassGrant::GRANT_WINDOW

    # (1) AUDIT FIRST. Metadata is CONTEXT ONLY — ids/types/reason/expiry/sensitivity_level.
    audit = AccessLog.security_event!(
      event_type: 'break_glass',
      request:    request,
      user:       current_user,
      metadata: {
        'reason'               => grant_reason,
        'custom_field_id'      => grant_custom_field_id,
        'custom_formable_type' => record.class.base_class.name,
        'custom_formable_id'   => record.id,
        'sensitivity_level'    => 'emergency_only',
        'expires_at'           => expires_at.iso8601
      }
    )

    # (2) FAIL-CLOSED: nil audit => the write blew up; NO grant without a successful audit row.
    if audit.nil?
      Rails.logger.error('[BreakGlass] audit write failed; aborting grant creation (fail-closed).')
      return deny('Emergency access could not be audited and was not granted. Please try again.')
    end

    # (3) Only now create the 1h grant.
    grant = BreakGlassGrant.new(
      user:                 current_user,
      custom_formable_type: record.class.base_class.name,
      custom_formable_id:   record.id,
      custom_field_id:      grant_custom_field_id,
      reason:               grant_reason,
      expires_at:           expires_at
    )

    if grant.save
      redirect_back fallback_location: root_path, notice: t('.granted', default: 'Emergency access granted for 1 hour. This action has been logged.')
    else
      redirect_back fallback_location: root_path, alert: (grant.errors.full_messages.to_sentence.presence || t('.failed', default: 'Emergency access could not be granted.'))
    end
  end

  private

  # Load the target (Client/Family/Partner) scoped to what current_user can :read. An out-of-scope
  # id is not in the relation -> nil. Client is friendly_id-slugged.
  def find_readable_record
    type = params[:custom_formable_type].to_s
    id   = params[:custom_formable_id].presence || params[:client_id].presence
    return nil unless BreakGlassGrant::CUSTOM_FORMABLE_TYPES.include?(type)
    return nil if id.blank?

    case type
    when 'Client'  then Client.accessible_by(current_ability).friendly.find(id)
    when 'Family'  then Family.accessible_by(current_ability).find(id)
    when 'Partner' then Partner.accessible_by(current_ability).find(id)
    end
  rescue ActiveRecord::RecordNotFound
    nil
  end

  def grant_custom_field_id
    params[:custom_field_id].presence&.to_i
  end

  def grant_reason
    params[:reason].to_s.strip
  end

  # A denied elevation is itself a security event (LOCKED: event_type "sensitive_field_denied").
  # Context-only metadata. Reuses the Phase 3 writer, which never raises into the request.
  def log_denied(record: nil, reason: nil)
    AccessLog.security_event!(
      event_type: 'sensitive_field_denied',
      request:    request,
      user:       current_user,
      metadata: {
        'reason'               => reason,
        'custom_field_id'      => grant_custom_field_id,
        'custom_formable_type' => (record ? record.class.base_class.name : params[:custom_formable_type].to_s.presence),
        'custom_formable_id'   => (record ? record.id : params[:custom_formable_id].presence),
        'sensitivity_level'    => 'emergency_only'
      }
    )
  end

  def deny(message)
    redirect_back fallback_location: root_path, alert: message
  end
end
