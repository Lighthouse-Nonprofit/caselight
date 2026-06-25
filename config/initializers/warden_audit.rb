# frozen_string_literal: true
#
# AU-2 (audit events) / AC-7 (unsuccessful logon attempts): capture FAILED logins
# and account lockouts in the tenant-isolated, append-only AccessLog.
#
# WHY a Warden hook (not SessionsController): a bad password never reaches
# SessionsController#create -- Warden throws(:warden) and Devise::FailureApp handles
# it. before_failure is the only reliable seam for failed-login + lockout logging.
# The two-step MFA SessionsController (password -> /users/two_factor) is NOT modified.
#
# Tenant note: Apartment's middleware runs BEFORE Warden, so Organization.current
# (and thus the AccessLog tenant default) is already set inside this hook.
#
# Resilience note: this runs in the request's failure path. It MUST NOT raise --
# AccessLog.security_event! already rescues+logs internally, but we wrap the whole
# body defensively because `env` can be shaped unexpectedly (e.g. non-Devise
# failures) and we must never convert an auth failure into a 500.

Warden::Manager.before_failure do |env, opts|
  begin
    request = ActionDispatch::Request.new(env)

    # Failure PHASE discriminator. before_failure also fires for a failed SECOND
    # factor in the two-step MFA flow (POST /users/two_factor) -- which carries the
    # OTP, not user[email]. We keep event_type "login_failure" (conservative AU-2),
    # but record metadata["factor"] so CC7.2 dashboards can separate password
    # brute-force from legitimate-user OTP fumbles. path/phase are not record
    # contents, so no PII is added.
    phase = request.path.to_s.include?("two_factor") ? "second_factor" : "password"

    # The attempted identifier. Devise nests sign-in params under the auth scope
    # (default :user). Fall back to a top-level :email if the scope is absent.
    scope  = (opts && opts[:scope]) || :user
    params = request.params || {}
    scoped = params[scope.to_s] || params[scope] || {}
    attempted_email = (scoped.is_a?(Hash) ? (scoped["email"] || scoped[:email]) : nil) ||
                      params["email"] || params[:email]
    attempted_email = attempted_email.to_s.strip
    attempted_email = nil if attempted_email.empty?

    # Resolve the actor (may be nil for a bogus/unknown email). user_email is
    # denormalized into AccessLog so the trail survives user deletion; we still
    # record the attempted email even when no User matches.
    user = nil
    if attempted_email
      begin
        user = User.find_by(email: attempted_email)
      rescue StandardError
        user = nil
      end
    end

    AccessLog.security_event!(
      event_type: "login_failure",
      request: request,
      user: user,
      metadata: {
        "attempted_email" => attempted_email,
        "factor"          => phase,
        "warden_message"  => (opts && opts[:message]).to_s.presence,
        "scope"           => scope.to_s
      }.compact
    )

    # If the attempted account is now locked (devise :lockable), record the
    # lockout as its own AC-7 event. access_locked? is the authoritative check
    # (covers both the failed-attempts threshold and an explicit admin lock).
    if user.respond_to?(:access_locked?) && user.access_locked?
      AccessLog.security_event!(
        event_type: "account_locked",
        request: request,
        user: user,
        metadata: { "attempted_email" => attempted_email }.compact
      )
    end
  rescue StandardError => e
    # Never let audit logging break authentication. security_event! is already
    # self-rescuing; this is the belt-and-suspenders guard for env/params shape.
    Rails.logger.error("[warden_audit] failed to record security event: #{e.class}: #{e.message}")
  end
end
