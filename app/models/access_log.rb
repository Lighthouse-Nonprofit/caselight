# frozen_string_literal: true

# AccessLog — the read-access + security-event audit store.
# FedRAMP AU-2/AU-12 (audit the access events themselves; paper_trail already
# covers the CHANGE audit in Postgres). SOC2 CC7.2/CC7.3.
#
# WHY Mongo (not Postgres/paper_trail): this is an append-only, high-volume,
# read-side trail; it lives in the shared history/audit Mongo db alongside the
# *_history models. Postgres is Apartment schema-per-tenant, but Mongo is ONE
# shared database -> we MUST tenant-isolate by hand (AU-9). We do it the same way
# ClientHistory does: a `tenant` field + a default_scope that pins reads/writes to
# the current org. A naive Mongo model with no tenant scope would leak audit rows
# across orgs, which is exactly the AU-9 risk this control is meant to close.
#
# Organization.current is nil outside a tenant (rails console, some Sidekiq jobs)
# -> use try(:short_name) in BOTH the default_scope and the field default lambda so
# the tenant resolution NEVER raises. A nil tenant simply means "unscoped context";
# it must not blow up logging.
class AccessLog
  include Mongoid::Document
  # Created-only timestamp: an audit row is born and never updated -> there is no
  # meaningful updated_at on an append-only record (and writing one would imply
  # mutability we explicitly forbid below).
  include Mongoid::Timestamps::Created

  # AU-9: pin every query to the current tenant. try(:short_name) tolerates a nil
  # Organization.current (console/jobs) without raising.
  default_scope { where(tenant: Organization.current.try(:short_name)) }

  field :tenant,        type: String, default: -> { Organization.current.try(:short_name) }

  # event_type taxonomy (the ONE coherent vocabulary shared by every write path):
  #   "read"           — a successful show/index of a sensitive resource
  #   "login_failure"  — a failed authentication attempt
  #   "account_locked" — the attempted account is now locked out
  #   "access_denied"  — an authenticated user was refused (CanCan/Pundit)
  field :event_type,    type: String

  field :user_id,       type: Integer  # nullable (unauthenticated events have no user)
  # DENORMALIZED actor handle: we keep the email on the row so the trail survives
  # the User being deleted. This is the ONE identifier we are allowed to store —
  # never any record CONTENTS (names/DOB/notes); only ids/types below.
  field :user_email,    type: String

  field :resource_type, type: String   # e.g. "Client" (nullable)
  field :resource_id,   type: String   # nullable; String so it tolerates non-int ids
  field :controller,    type: String
  field :action,        type: String
  field :http_method,   type: String
  field :path,          type: String
  field :remote_ip,     type: String
  field :request_id,    type: String
  # metadata carries ONLY non-sensitive context (attempted_email, reason, source,
  # factor, warden message). NEVER stuff record attributes (names/DOB/notes) here —
  # there is no structural guard, so this is a hard review rule.
  field :metadata,      type: Hash, default: {}

  # Query paths the SOC2/FedRAMP reviewer actually runs: recent events per tenant,
  # a user's activity, and "who touched this resource".
  index({ tenant: 1, created_at: -1 })
  index({ tenant: 1, user_id: 1, created_at: -1 })
  index({ tenant: 1, resource_type: 1, resource_id: 1 })

  # AU-11: age-based selection used by the sanctioned retention purge
  # (lib/tasks/audit.rake). Mongoid criteria; composes on top of the tenant
  # default_scope OR on .unscoped (the purge runs unscoped to span all tenants).
  # to_i coerces the rake/ENV string form of DAYS.
  scope :older_than, ->(days) { where(:created_at.lt => days.to_i.days.ago) }

  # WORM at the app layer: an audit row is immutable once written. True WORM is an
  # infra hand-off (storage-level retention lock), but the app must never mutate or
  # delete a row in normal flow -> raise on update/destroy. The retention purge
  # (lib/tasks/audit.rake) is the ONE sanctioned removal path and uses delete_all,
  # which skips these callbacks by design.
  before_update  { raise RuntimeError, "AccessLog is append-only; rows cannot be updated" }
  before_destroy { raise RuntimeError, "AccessLog is append-only; rows cannot be destroyed (use the sanctioned retention purge)" }

  class << self
    # Record a successful READ (show/index) from a controller instance. AU-2/AU-12.
    # Pulls everything from the controller's request + current_user; stores ONLY
    # ids/types (never contents). Resilient: a logging failure must never 500 a
    # request, so the whole body is rescued and downgraded to a Rails.logger.error.
    def record_read!(controller)
      req  = controller.request
      user = controller.respond_to?(:current_user) ? controller.current_user : nil

      attrs = {
        event_type:    "read",
        user_id:       user.try(:id),
        user_email:    user.try(:email),
        resource_type: derive_resource_type(controller),
        resource_id:   controller.params[:id].presence,
        controller:    controller.controller_name,
        action:        controller.action_name,
        http_method:   req.request_method,
        path:          req.fullpath,
        remote_ip:     req.remote_ip,
        request_id:    req.request_id
      }

      write!(attrs)
    rescue => e
      # Never let auditing break the request it is auditing.
      Rails.logger.error("[AccessLog] record_read! failed: #{e.class}: #{e.message}")
      nil
    end

    # Record a security event (login_failure / account_locked / access_denied) from
    # a raw ActionDispatch::Request (Warden hook has env, the rescues have request).
    # user is optional — unauthenticated failures have none. Same resilience contract.
    def security_event!(event_type:, request:, user: nil, metadata: {})
      attrs = {
        event_type:  event_type,
        user_id:     user.try(:id),
        user_email:  user.try(:email),
        controller:  (request.params[:controller] if request.respond_to?(:params)),
        action:      (request.params[:action] if request.respond_to?(:params)),
        http_method: request.request_method,
        path:        request.fullpath,
        remote_ip:   request.remote_ip,
        request_id:  request.request_id,
        metadata:    metadata || {}
      }

      write!(attrs)
    rescue => e
      Rails.logger.error("[AccessLog] security_event! failed: #{e.class}: #{e.message}")
      nil
    end

    private

    # Single write seam: persist to Mongo AND emit one compact structured JSON line
    # to Rails.logger so the event also lands in the lograge JSON stream / WORM sink
    # (AU-3). Defense in depth: even if Mongo is unavailable, the line survives.
    def write!(attrs)
      log = create!(attrs)
      Rails.logger.info(audit_line(log).to_json)
      log
    end

    # Compact, content-free JSON for the log sink. tag lets a downstream pipeline
    # filter audit lines out of the request-log noise.
    def audit_line(log)
      {
        tag:           "access_log",
        event_type:    log.event_type,
        tenant:        log.tenant,
        user_id:       log.user_id,
        user_email:    log.user_email,
        resource_type: log.resource_type,
        resource_id:   log.resource_id,
        controller:    log.controller,
        action:        log.action,
        http_method:   log.http_method,
        path:          log.path,
        remote_ip:     log.remote_ip,
        request_id:    log.request_id,
        created_at:    log.created_at.try(:iso8601)
      }
    end

    # Derive "Client" from a ClientsController without depending on a specific ivar
    # name across the four controllers (briefing: do NOT depend on @client/@assessment/...).
    # controller_name is e.g. "clients" -> "Client"; "progress_notes" -> "ProgressNote".
    def derive_resource_type(controller)
      controller.controller_name.classify
    rescue
      nil
    end
  end
end
